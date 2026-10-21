#!/usr/bin/env python3
"""parse-cart.py - 把 sweep 的渲染文本解析成购物车条目（只读解析，不联网）。

改进（v3）：
- 不再按标题去重（购物车里同款不同 SKU 是两行）
- 首件（无「信用卡支付」行）单独补一条
- 原价取最后一个 ￥ 数字组，数量取最后一组之后的首个 1-3 位整数
"""
import json, re, sys, pathlib

def load(dirpath):
    files = sorted(pathlib.Path(dirpath).glob("round-*.txt"))
    if not files:
        return ""
    return files[-1].read_text(encoding="utf-8", errors="replace").replace("\r", "")

def parse_price(lines, i):
    j, buf = i + 1, ""
    if j < len(lines) and re.fullmatch(r"[0-9]+", lines[j]):
        buf += lines[j]; j += 1
    if j < len(lines) and lines[j] == ".":
        buf += "."; j += 1
        if j < len(lines) and re.fullmatch(r"[0-9]+", lines[j]):
            buf += lines[j]; j += 1
    try:
        return float(buf), j
    except ValueError:
        return None, i + 1

PAY = ("信用卡支付", "花呗", "余额宝")

def parse(dirpath):
    text = load(dirpath)
    lines = [l.strip() for l in text.split("\n")]
    for i, l in enumerate(lines):
        if l == "猜你喜欢":
            lines = lines[:i]
            break
    pay_idx = [i for i, l in enumerate(lines) if l in PAY]
    starts = []
    for k, i in enumerate(pay_idx):
        t = i - 1
        while t >= 0 and lines[t] in ("款式缺货", "重新选择规格", ""):
            t -= 1
        if t < 0 or len(lines[t]) < 6:
            continue
        starts.append((t, i, k))
    items = []
    for n, (t, i, k) in enumerate(starts):
        end = starts[n + 1][0] if n + 1 < len(starts) else len(lines)
        seg = lines[i:end]
        title = lines[t]
        s = t - 1
        while s >= 0 and (lines[s] == "" or lines[s] in ("款式缺货", "重新选择规格", "淘宝", "天猫")
                          or lines[s].startswith(("退货宝", "极速退款", "假一赔四", "大促价保", "7天无理由", "官方立减", "消费券", "补贴", "满"))):
            s -= 1
        shop = lines[s] if 0 <= s < len(lines) and 2 <= len(lines[s]) < 40 and not re.fullmatch(r"[0-9.]+", lines[s]) else ""
        spec = next((l.split("：", 1)[1] for l in seg if l.startswith("商品规格：") or l.startswith("颜色分类：") or l.startswith("套餐类型：") or l.startswith("内存容量：")), "")
        # 价格组定位：淘宝每行模板为
        #   平台加补后 / ￥ 现价 [ / 距加入降 / ￥ 降额 ] [ / ￥ 原价 ] / 数量
        # 有「距加入降」时第三组才是原价；否则第二组即原价。数量取所用最后一组之后的首个 1-3 位整数。
        anchor = seg.index("平台加补后") if "平台加补后" in seg else None
        stop = None
        if anchor is None:
            # 无「平台加补后」行（如「重新选择规格」模板）：只认支付行后的第一个价格组，避免串行
            for k in range(len(seg) - 1):
                if seg[k] == "￥" and k <= 8:
                    anchor = k - 1
                    stop = k + 8
                    break
        groups, j = [], (anchor + 1 if anchor is not None else 0)
        limit = stop if stop is not None else len(seg)
        while j < min(limit, len(seg)):
            if seg[j] == "￥":
                v, j2 = parse_price(seg, j)
                if v is not None:
                    groups.append((v, j2))
                j = max(j2, j + 1)
            else:
                j += 1
            if len(groups) >= 3:
                break
        # 「距加入降」出现在第一组与第二组之间时，第二组是降额，第三组才是原价
        drop_between = False
        if len(groups) >= 2:
            gap = " ".join(seg[groups[0][1]:groups[1][1]])
            drop_between = "距加入降" in gap
        price = groups[0][0] if groups else None
        if drop_between and len(groups) >= 3:
            orig = groups[2][0]
            tail_from = groups[2][1]
        elif drop_between:
            orig = None
            tail_from = groups[1][1]
        elif len(groups) >= 2 and groups[1][0] > groups[0][0]:
            orig = groups[1][0]
            tail_from = groups[1][1]
        else:
            orig = None
            tail_from = groups[0][1] if groups else 0
        qty = None
        for l in seg[tail_from:]:
            if re.fullmatch(r"[0-9]{1,3}", l):
                qty = int(l); break
        prices = [g[0] for g in groups]
        joined = " ".join(seg)
        status = "需重选规格" if "重新选择规格" in seg else ("失效" if "宝贝已不能购买" in joined else ("即将售罄" if "即将售罄" in joined else "可购买"))
        items.append({
            "shop": shop, "title": title, "spec": spec,
            "price": price,
            "orig_price": orig,
            "qty": qty, "status": status, "prices_raw": prices[:5],
        })
    # 首件：位于第一个「信用卡支付」之前、带价格组但无支付行的条目
    head = lines[:starts[0][1] if starts else 0]
    if head:
        pi = [i for i, l in enumerate(head) if l == "￥"]
        if pi:
            # 找标题：第一条长度>8 且不以价格标签开头的行（跳过账号/导航区）
            cand = None
            for i, l in enumerate(head):
                if i > 20 and len(l) > 8 and not l.startswith(("￥", "您有", "全部商品")):
                    cand = i; break
            if cand is not None:
                prices, j, last_end = [], 0, 0
                while j < len(head):
                    if head[j] == "￥":
                        v, j2 = parse_price(head, j)
                        if v is not None:
                            prices.append(v)
                        last_end = j2; j = max(j2, j + 1)
                    else:
                        j += 1
                qty = None
                for l in head[last_end:]:
                    if re.fullmatch(r"[0-9]{1,3}", l):
                        qty = int(l); break
                shop = ""
                for s in range(cand - 1, 0, -1):
                    if head[s] and 2 <= len(head[s]) < 40:
                        shop = head[s]; break
                items.insert(0, {"shop": shop, "title": head[cand], "spec": "",
                                 "price": prices[0] if prices else None,
                                 "orig_price": prices[-1] if len(prices) > 1 else None,
                                 "qty": qty, "status": "可购买", "prices_raw": prices[:5]})
    return items

if __name__ == "__main__":
    d = sys.argv[1] if len(sys.argv) > 1 else "raw"
    items = parse(d)
    out = {"items": items, "count": len(items),
           "qty_sum": sum(i["qty"] or 0 for i in items),
           "amount_sum": round(sum((i["price"] or 0) * (i["qty"] or 0) for i in items), 2)}
    print(json.dumps(out, ensure_ascii=False, indent=1))
