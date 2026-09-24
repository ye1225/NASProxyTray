# -*- coding: utf-8 -*-
"""
NASProxyTray 三轮测速（交互版，零依赖，Python 3.7+）

流程（按提示操作即可）：
  1) 打开代理【全局模式】  -> 回车 -> 第一轮：所有站点经代理
  2) 打开代理【规则模式】  -> 回车 -> 第二轮：国内直连、国外经代理
  3) 【关闭代理】          -> 回车 -> 第三轮：全部直连
  结束 -> 回车 -> 在脚本同目录保存 speedtest_*.log / *.json

脚本每轮开始都会读注册表核对系统代理状态，不符会提示重试；
不需要指定代理地址，一切跟着 NASProxyTray 的实际状态走。
"""
import socket, ssl, time, json, os, sys, re, platform, datetime

try:
    sys.stdout.reconfigure(errors='replace')
except Exception:
    pass

DOMESTIC = ['www.baidu.com', 'www.qq.com', 'www.taobao.com', 'www.bilibili.com', 'www.jd.com']
FOREIGN  = ['github.com', 'www.cloudflare.com']
ATTEMPTS = 3          # 每站每轮测几次
TIMEOUT  = 10

CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE
CTX12 = ssl.create_default_context()   # 兜底：部分代理链路与 TLS1.3 握手不兼容
CTX12.check_hostname = False
CTX12.verify_mode = ssl.CERT_NONE
CTX12.maximum_version = ssl.TLSVersion.TLSv1_2

def read_proxy_state():
    """读注册表 -> ('global',(host,port)) | ('pac',(host,port)|None) | ('off',None)"""
    try:
        import winreg
        k = winreg.OpenKey(winreg.HKEY_CURRENT_USER,
                           r'Software\Microsoft\Windows\CurrentVersion\Internet Settings')
        def q(n):
            try: return winreg.QueryValueEx(k, n)[0]
            except FileNotFoundError: return None
        enable = q('ProxyEnable')
        server = q('ProxyServer')
        pacurl = q('AutoConfigURL')
        if enable and server:
            s = server
            if ';' in s or '=' in s:
                for part in s.split(';'):
                    if part.lower().startswith(('https=', 'http=')):
                        s = part.split('=', 1)[1]; break
            if s.startswith('http://'): s = s[7:]
            if ':' in s:
                h, p = s.rsplit(':', 1)
                return 'global', (h, int(p))
        if pacurl:
            return 'pac', parse_pac_proxy(pacurl)
    except Exception as e:
        print('  (读注册表失败: %s)' % e)
    return 'off', None

def parse_pac_proxy(url):
    """从 PAC 文件里抠出 PROXY host:port"""
    try:
        if re.match(r'^https?://', url, re.I):
            import urllib.request
            raw = urllib.request.urlopen(url, timeout=5).read()
        else:
            path = url
            if path.startswith('file:///'): path = path[8:]
            elif path.startswith('file://'):  path = path[7:]
            raw = open(path, 'rb').read()
        m = re.search(rb'PROXY\s+([0-9A-Za-z.\-]+:\d+)', raw)
        if m:
            h, p = m.group(1).decode().rsplit(':', 1)
            return (h, int(p))
    except Exception as e:
        print('  (解析 PAC 失败: %s)' % e)
    return None

def state_desc(state, proxy):
    if state == 'global': return '全局代理 -> %s:%d' % proxy
    if state == 'pac':    return '规则模式(PAC) -> 代理 %s' % (('%s:%d' % proxy) if proxy else '解析失败!')
    return '代理已关闭（全部直连）'

def wait_for_state(expect, note):
    """提示用户操作，回车后核对注册表状态；不符可重试，输 s 强行继续"""
    while True:
        input('\n>> 请%s，然后按回车…' % note)
        state, proxy = read_proxy_state()
        print('   检测到: %s' % state_desc(state, proxy))
        if state == expect and (expect != 'pac' or proxy):
            return proxy
        if state == expect and expect == 'off':
            return None
        ans = input('   !! 状态与预期不符。回车=重新核对，s=不管了直接测: ').strip().lower()
        if ans == 's':
            return proxy

def local_ips():
    ips = []
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = info[4][0]
            if ip not in ips: ips.append(ip)
    except Exception:
        pass
    return ips

def one_request(site, proxy):
    """proxy=None 直连；否则 CONNECT 隧道。返回分阶段耗时。"""
    r = {'dns': 0.0, 'tcp': 0.0, 'tls': 0.0, 'ttfb': 0.0, 'total': 0.0,
         'status': 0, 'bytes': 0, 'err': None, 'tls12': False}
    t0 = time.perf_counter()
    try:
        if proxy:
            t1 = time.perf_counter()
            sock = socket.create_connection(proxy, timeout=TIMEOUT)
            r['tcp'] = time.perf_counter() - t1
            sock.sendall(('CONNECT %s:443 HTTP/1.1\r\nHost: %s:443\r\n\r\n' % (site, site)).encode())
            resp = b''
            while b'\r\n\r\n' not in resp:
                c = sock.recv(4096)
                if not c: raise OSError('empty CONNECT reply')
                resp += c
            line = resp.split(b'\r\n', 1)[0]
            if b' 200 ' not in line:
                raise OSError('CONNECT failed: ' + line.decode(errors='replace'))
        else:
            t1 = time.perf_counter()
            addr = socket.getaddrinfo(site, 443, socket.AF_INET, socket.SOCK_STREAM)[0]
            r['dns'] = time.perf_counter() - t1
            t1 = time.perf_counter()
            sock = socket.create_connection(addr[4], timeout=TIMEOUT)
            r['tcp'] = time.perf_counter() - t1
        t1 = time.perf_counter()
        try:
            tls = CTX.wrap_socket(sock, server_hostname=site)
        except ssl.SSLError:
            sock.close()
            sock = socket.create_connection(proxy, timeout=TIMEOUT) if proxy else \
                   socket.create_connection(socket.getaddrinfo(site, 443, socket.AF_INET, socket.SOCK_STREAM)[0][4], timeout=TIMEOUT)
            if proxy:
                sock.sendall(('CONNECT %s:443 HTTP/1.1\r\nHost: %s:443\r\n\r\n' % (site, site)).encode())
                resp = b''
                while b'\r\n\r\n' not in resp:
                    c = sock.recv(4096)
                    if not c: raise OSError('empty CONNECT reply(2)')
                    resp += c
            tls = CTX12.wrap_socket(sock, server_hostname=site)
            r['tls12'] = True
        r['tls'] = time.perf_counter() - t1
        tls.sendall(('GET / HTTP/1.1\r\nHost: %s\r\nUser-Agent: Mozilla/5.0 (speedtest3)\r\n'
                     'Accept: */*\r\nConnection: close\r\n\r\n' % site).encode())
        t1 = time.perf_counter()
        head = b''
        while b'\r\n\r\n' not in head:
            c = tls.recv(4096)
            if not c: break
            head += c
        r['ttfb'] = time.perf_counter() - t1
        if b'\r\n\r\n' in head:
            hp, body = head.split(b'\r\n\r\n', 1)
            try: r['status'] = int(hp.split(b'\r\n')[0].split()[1])
            except Exception: r['status'] = -1
            n = len(body)
            while n < 65536:
                c = tls.recv(65536)
                if not c: break
                n += len(c)
            r['bytes'] = n
        tls.close()
    except Exception as e:
        r['err'] = '%s: %s' % (type(e).__name__, str(e)[:140])
    r['total'] = time.perf_counter() - t0
    return r

def mean(xs):
    return sum(xs) / len(xs) if xs else float('nan')

def fmt(site, r):
    if r['err']:
        return '%-20s ERROR %s' % (site, r['err'])
    fb = ' [TLS1.2]' if r.get('tls12') else ''
    return ('%-20s total=%7.1fms dns=%5.1f tcp=%6.1f tls=%6.1f ttfb=%6.1f http=%d %dB%s'
            % (site, r['total']*1000, r['dns']*1000, r['tcp']*1000,
               r['tls']*1000, r['ttfb']*1000, r['status'], r['bytes'], fb))

def run_round(name, proxy_for, fh):
    """proxy_for(site) -> proxy 或 None"""
    print('\n—— 第%s轮 开始 ——' % name)
    fh.write('\n==== 第%s轮 ====\n' % name)
    results = []
    for site in DOMESTIC + FOREIGN:
        proxy = proxy_for(site)
        runs = []
        for i in range(ATTEMPTS):
            r = one_request(site, proxy)
            runs.append(r)
            results.append({'round': name, 'site': site, 'via': 'proxy' if proxy else 'direct', **r})
            print('  %s' % fmt(site, r))
            fh.write('  %s\n' % fmt(site, r))
            time.sleep(0.3)
        ok = [x['total'] * 1000 for x in runs if not x['err']]
        line = ('  -> %-20s 平均 %7.1f ms (%d/%d)' % (site, mean(ok), len(ok), ATTEMPTS)) if ok \
               else '  -> %-20s 全部失败' % site
        print(line); fh.write(line + '\n')
    return results

def main():
    stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    here = os.path.dirname(os.path.abspath(__file__))
    log_path = os.path.join(here, 'speedtest_%s.log' % stamp)
    fh = open(log_path, 'a', encoding='utf-8')   # 边测边写，中途关窗口也有已测数据
    fh.write('=' * 72 + '\nNASProxyTray 三轮测速 %s\n' % datetime.datetime.now().isoformat(timespec='seconds'))
    fh.write('主机: %s (%s, Python %s)\n本机 IPv4: %s\n每站每轮 %d 次\n'
             % (platform.node(), platform.platform(), platform.python_version(),
                ', '.join(local_ips() or ['?']), ATTEMPTS))
    fh.write('站点: 国内 %s / 国外 %s\n' % (DOMESTIC, FOREIGN))

    print('=' * 60)
    print(' NASProxyTray 三轮测速')
    print(' 共三轮：全局 / 规则 / 关闭。每轮前请按提示切换模式。')
    print('=' * 60)

    all_results = []

    p1 = wait_for_state('global', '打开 NASProxyTray 的【全局模式】（托盘图标变蓝）')
    all_results += run_round('1-全局', lambda s: p1, fh)

    p2 = wait_for_state('pac', '切换到【规则模式】（托盘图标变绿）')
    all_results += run_round('2-规则', lambda s: None if s in DOMESTIC else p2, fh)

    wait_for_state('off', '【关闭代理】（托盘图标变灰；右上角叉收起不影响）')
    all_results += run_round('3-关闭', lambda s: None, fh)

    # 汇总
    fh.write('\n==== 汇总（平均，ms）====\n')
    print('\n==== 汇总（平均，ms）====')
    hdr = '%-20s %8s %8s %8s %8s %8s' % ('站点', '全局', '规则', '关闭', '规则-关闭', '全局-关闭')
    fh.write(hdr + '\n'); print(hdr)
    for site in DOMESTIC:
        def avg(rd):
            xs = [x['total'] * 1000 for x in all_results if x['round'] == rd and x['site'] == site and not x['err']]
            return mean(xs)
        g, u, o = avg('1-全局'), avg('2-规则'), avg('3-关闭')
        row = '%-20s %8.1f %8.1f %8.1f %+8.1f %+8.1f' % (site, g, u, o, u - o, g - o)
        fh.write(row + '\n'); print(row)
    for site in FOREIGN:
        for rd in ('1-全局', '2-规则', '3-关闭'):
            ok = [x for x in all_results if x['round'] == rd and x['site'] == site and not x['err']]
            tot = [x['total'] * 1000 for x in ok]
            line = '%-12s %-8s %d/%d 成功%s' % (site, rd, len(ok), ATTEMPTS,
                   ('  平均 %.1f ms' % mean(tot)) if tot else '')
            fh.write(line + '\n'); print(line)

    json_path = os.path.join(here, 'speedtest_%s.json' % stamp)
    with open(json_path, 'w', encoding='utf-8') as jf:
        json.dump({'attempts': ATTEMPTS, 'results': all_results}, jf, ensure_ascii=False, indent=1)
    fh.write('\n日志: %s\n' % log_path)
    fh.close()
    input('\n测试完成！回车保存并退出…')
    print('已保存:\n  %s\n  %s\n把这两个文件拿回来即可分析。' % (log_path, json_path))
    input('按回车关闭窗口…')

if __name__ == '__main__':
    main()
