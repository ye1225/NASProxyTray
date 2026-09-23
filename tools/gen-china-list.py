#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
重新生成 src/35-china-direct.ps1 里的「国内常见域名直连」清单。

用法:
    python tools/gen-china-list.py

依赖: Python 3 标准库 + 网络（走 jsDelivr CDN，直连 GitHub raw 通常不通）。
下载的原始清单缓存在 build/list-cache/，重复运行不会重新下载。

三个来源交叉确认，只有出现在 felixonmars 或 ChinaMax 任一清单里的域名才会被收录，
避免把国外站点误当成国内站。
"""

import io
import os
import re
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, 'build', 'list-cache')
TARGET = os.path.join(ROOT, 'src', '35-china-direct.ps1')

SOURCES = {
    'felix.conf': 'https://cdn.jsdelivr.net/gh/felixonmars/dnsmasq-china-list@master/accelerated-domains.china.conf',
    'cmax.list': 'https://cdn.jsdelivr.net/gh/blackmatrix7/ios_rule_script@master/rule/Surge/ChinaMax/ChinaMax_Domain.list',
    'acl.list': 'https://cdn.jsdelivr.net/gh/ACL4SSR/ACL4SSR@master/Clash/ChinaDomain.list',
}

# 按品牌关键词从「两源交集」里捞域名。按域名段精确匹配，避免 zhihu 误伤 zhihuiXxx。
BRANDS = """
baidu bdstatic bdimg hao123 bcebos
alibaba aliyun alicdn alipay alimama taobao tmall aliyundrive dingtalk umeng
tencent qq weixin wechat gtimg qpic qlogo qcloud qqmail tencentmusic
jingdong jd 360buy
bytedance douyin toutiao feishu lark ixigua huoshan volcengine amemv
bilibili hdslb bilivideo
zhihu zhimg
weibo sina sinajs sinaimg weibocdn
sohu ifeng
netease 163 126 yeah youdao
meituan dianping
pinduoduo pddpic
xiaohongshu xhscdn
kuaishou
xiaomi miui
huawei hicloud
oppo vivo
amap autonavi
didi
ctrip qunar elong
csdn juejin gitee oschina cnblogs segmentfault
douban
iqiyi youku mgtv hunantv
zhaopin lagou 51job
tianyancha qcc
smzdm hupu suning yiche autohome dongchedi
ximalaya qingting xunlei kugou kuwo migu
huya douyu
wps kingsoft
ele 58 ceair qiyi yunpan dnspod
chinaunicom cmbchina icbc ccb abc bocom
""".split()

# 自身常被访问、但可能不在上游清单里的域名
MANUAL = """
12306.cn feishu.cn wps.cn juejin.cn v2ex.com nodeseek.com
tuna.tsinghua.edu.cn zol.com.cn pconline.com.cn
gitee.com cnblogs.com oschina.net segmentfault.com
yuque.com aliyundrive.com smzdm.com hupu.com
""".split()

# 被墙站绝不能进直连清单 —— 收录了就说明上游数据有问题，宁可剔掉
WALLED = """
google youtube github twitter facebook wikipedia reddit telegram whatsapp
instagram openai chatgpt claude anthropic netflix twitch discord medium pixiv
steam dropbox slack zoom bbc nytimes cloudflare amazon
""".split()

HEADER = """# ---------------------------------------------------------------
# 35-china-direct.ps1 - 内置「国内常见域名」直连清单
# ---------------------------------------------------------------
# 内置 PAC 的「智能分流」策略用它判断哪些域名直连，
# 不在清单里的全部交给用户的代理（代理自己还有一层分流规则），
# 所以这里只需要覆盖常见站，不必求全。
#
# 本文件由 tools/gen-china-list.py 生成，请勿手工大改。
# 重新生成： python tools/gen-china-list.py
#
# 数据来源（三源交叉确认，均为公开数据）：
#   felixonmars/dnsmasq-china-list  accelerated-domains.china.conf
#   blackmatrix7/ios_rule_script    ChinaMax
#   ACL4SSR/ACL4SSR                 ChinaDomain.list
# ---------------------------------------------------------------

$script:ChinaDirectDomains = @(
"""

FOOTER = """# .cn 全域直连（政务 / 学校 / 银行 / 大量国内站点都在这个后缀下）
$script:ChinaDirectSuffixes = @('.cn')
"""


def fetch(name, url):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, name)
    if not os.path.exists(path) or os.path.getsize(path) < 1000:
        sys.stderr.write('downloading %s ...\n' % url)
        req = urllib.request.Request(url, headers={'User-Agent': 'curl/8'})
        with urllib.request.urlopen(req, timeout=120) as r, io.open(path, 'wb') as f:
            f.write(r.read())
    return path


def load_felix(path):
    s = set()
    with io.open(path, encoding='utf-8', errors='replace') as f:
        for line in f:
            m = re.match(r'server=/([^/]+)/', line.strip())
            if m:
                s.add(m.group(1).lower().strip('.'))
    return s


def load_surge(path):
    s = set()
    with io.open(path, encoding='utf-8', errors='replace') as f:
        for line in f:
            t = line.strip()
            if not t or t.startswith('#'):
                continue
            if ',' in t:
                t = t.split(',', 1)[1].strip().lower()
            s.add(t.lstrip('.'))
    return s


def main():
    felix = load_felix(fetch('felix.conf', SOURCES['felix.conf']))
    cmax = load_surge(fetch('cmax.list', SOURCES['cmax.list']))
    acl = load_surge(fetch('acl.list', SOURCES['acl.list']))

    trusted = felix | cmax
    both = felix & cmax

    sys.stderr.write('felix=%d cmax=%d acl=%d\n' % (len(felix), len(cmax), len(acl)))

    # 1) ACL4SSR 精选里被上游确认的（常见站骨架）
    base = set(d for d in acl if d in trusted or any(d.endswith('.' + x) for x in trusted))

    # 2) 按品牌关键词从两源交集里捞
    brand_hits = set()
    for d in both:
        segs = set(d.split('.'))
        for b in BRANDS:
            if b in segs:
                brand_hits.add(d)
                break

    final = sorted((base | brand_hits) | set(MANUAL))

    # 3) 自检：剔掉被墙站
    bad = set()
    for d in final:
        if set(d.split('.')) & set(WALLED):
            bad.add(d)
    final = [d for d in final if d not in bad]

    # 4) 输出
    lines = []
    for i in range(0, len(final), 6):
        grp = final[i:i + 6]
        lines.append('    ' + ', '.join("'%s'" % g for g in grp) + ',')

    body = '\n'.join(lines)
    body = body.rstrip(',') + '\n'

    with io.open(TARGET, 'w', encoding='utf-8-sig', newline='\r\n') as f:
        f.write(HEADER + body + ')\n\n' + FOOTER)

    sys.stderr.write('written %s  domains=%d  (walled removed=%d)\n' % (TARGET, len(final), len(bad)))


if __name__ == '__main__':
    main()
