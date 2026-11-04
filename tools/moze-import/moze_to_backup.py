"""Convert a decoded MOZE backup (JSON tables from realmdump) into a 記帳本 backup file.

Usage: python3 moze_to_backup.py <realmdump-output-dir> <out.json>

The output matches BackupFile in BudgetApp/Services/Backup.swift and is restored in the
app via 帳戶 → 設定、分類與備份 → 從備份還原.
"""
import collections
import datetime
import json
import sys
import uuid

NAMESPACE = uuid.UUID("6f0b5a8e-6a43-4b8e-9d1c-1f1c0de0a0a0")

# MOZE stores built-in names as localization keys; user-made ones are plain text.
NAMES = {
    "CATEGORY_LUNCH": "午餐", "CATEGORY_DINNER": "晚餐", "CATEGORY_SNACKS": "點心", "CATEGORY_BREAKFAST": "早餐",
    "CATEGORY_FRUITS": "水果", "CATEGORY_DRINKS": "飲料", "coffee": "咖啡",
    "CATEGORY_GAME": "遊戲", "CATEGORY_MUSIC": "音樂", "CATEGORY_MOVIE": "電影", "CATEGORY_PLAYGROUND": "遊樂園",
    "CATEGORY_VIDEO": "影音", "CATEGORY_GAMBLING": "博弈", "CATEGORY_EXHIBITION": "展覽", "CATEGORY_RECREATION": "休閒",
    "HSR": "高鐵", "CATEGORY_TAXI": "計程車", "CATEGORY_GAS": "加油", "CATEGORY_MOTO": "機車", "CATEGORY_TRAIN": "火車",
    "CATEGORY_BIKE": "腳踏車", "CATEGORY_AIRPLANE": "機票", "CATEGORY_SUBWAY": "捷運", "CATEGORY_CAR": "汽車",
    "CATEGORY_PARKING": "停車",
    "CATEGORY_SALARY": "薪水", "CATEGORY_REPAYMENT": "還款", "CATEGORY_BONUS": "獎金", "CATEGORY_INTEREST": "利息",
    "CATEGORY_LOTTERY": "中獎",
    "CATEGORY_CLOTHING": "衣服", "CATEGORY_SUPERMARKET": "超市", "CATEGORY_SHOES": "鞋子", "CATEGORY_3C": "3C",
    "CATEGORY_ACCESSORY": "配件", "CATEGORY_BAG": "包包", "CATEGORY_GIFT": "禮物",
    "CATEGORY_OTHERS": "其他",
    "CATEGORY_FURNITURE": "家具", "CATEGORY_GROCERIES": "日用品", "CATEGORY_LAUNDRY": "洗衣", "CATEGORY_FUEL": "瓦斯",
    "CATEGORY_REPAIR": "修繕", "CATEGORY_APPLIANCE": "家電", "CATEGORY_INTERNET": "網路", "CATEGORY_ELECTRICITY": "電費",
    "CATEGORY_PHONE": "電話費", "CATEGORY_WATER": "水費", "CATEGORY_RENT": "房租", "CATEGORY_SUBSCRIPTION": "訂閱",
    "CATEGORY_NURSING": "照護",
    "CATEGORY_INSURANCE": "保險", "CATEGORY_SOCIAL": "社交", "CATEGORY_MOBILE": "手機", "CATEGORY_TAX": "稅金",
    "CATEGORY_MASSAGE": "按摩", "CATEGORY_ACCOMMODATION": "住宿", "CATEGORY_SALON": "美容",
    "CATEGORY_HOSPITAL": "看醫生", "CATEGORY_MEDICINE": "藥品", "CATEGORY_TOOTH_CARE": "牙齒保健",
    "CATEGORY_SUPPLIES": "醫療用品", "CATEGORY_EXAMINATION": "健康檢查",
    "CATEGORY_TRANSFER": "轉帳", "CATEGORY_ADJUSTMENT": "餘額調整",
    "PROJECT_LIVING": "生活", "PROJECT_WORK": "工作", "PROJECT_TRAVEL": "旅行", "PROJECT_FAMILY": "家庭",
    "Monthly Statistics": "每月統計",
}
# Same key means different things as income vs expense.
INCOME_NAMES = {"CATEGORY_INVESTMENT": "投資收益"}
EXPENSE_NAMES = {"CATEGORY_INVESTMENT": "投資"}

SYMBOLS = {
    "CATEGORY_LUNCH": "fork.knife", "CATEGORY_DINNER": "takeoutbag.and.cup.and.straw", "CATEGORY_SNACKS": "birthday.cake",
    "CATEGORY_BREAKFAST": "sun.horizon", "CATEGORY_FRUITS": "leaf", "CATEGORY_DRINKS": "mug", "coffee": "cup.and.saucer",
    "CATEGORY_GAME": "gamecontroller", "CATEGORY_MUSIC": "music.note", "CATEGORY_MOVIE": "film",
    "CATEGORY_PLAYGROUND": "sparkles", "CATEGORY_VIDEO": "play.rectangle", "CATEGORY_GAMBLING": "dice",
    "CATEGORY_EXHIBITION": "photo.artframe", "CATEGORY_RECREATION": "figure.walk",
    "HSR": "train.side.front.car", "CATEGORY_TAXI": "car", "CATEGORY_GAS": "fuelpump", "CATEGORY_MOTO": "scooter",
    "CATEGORY_TRAIN": "tram", "CATEGORY_BIKE": "bicycle", "CATEGORY_AIRPLANE": "airplane", "CATEGORY_SUBWAY": "tram.fill",
    "CATEGORY_CAR": "car", "CATEGORY_PARKING": "parkingsign",
    "CATEGORY_SALARY": "banknote", "fix": "wrench.and.screwdriver", "CATEGORY_REPAYMENT": "arrow.uturn.left.circle",
    "CATEGORY_BONUS": "dollarsign.circle", "CATEGORY_INTEREST": "percent",
    "CATEGORY_INVESTMENT": "chart.line.uptrend.xyaxis", "loan": "creditcard", "CATEGORY_LOTTERY": "ticket",
    "CATEGORY_CLOTHING": "tshirt", "CATEGORY_SUPERMARKET": "cart", "CATEGORY_SHOES": "shoeprints.fill",
    "CATEGORY_3C": "desktopcomputer", "CATEGORY_ACCESSORY": "eyeglasses", "CATEGORY_BAG": "bag", "CATEGORY_GIFT": "gift",
    "CATEGORY_OTHERS": "ellipsis", "last balance": "equal.circle", "捐款": "heart",
    "CATEGORY_FURNITURE": "sofa", "CATEGORY_GROCERIES": "basket", "CATEGORY_LAUNDRY": "washer", "CATEGORY_FUEL": "flame",
    "CATEGORY_REPAIR": "hammer", "管理費": "building.2", "CATEGORY_APPLIANCE": "refrigerator", "CATEGORY_INTERNET": "wifi",
    "CATEGORY_ELECTRICITY": "bolt", "CATEGORY_PHONE": "phone", "CATEGORY_WATER": "drop", "CATEGORY_RENT": "house",
    "cleaning": "sparkles", "CATEGORY_SUBSCRIPTION": "repeat",
    "CATEGORY_NURSING": "figure.and.child.holdinghands",
    "理髮": "scissors", "CATEGORY_INSURANCE": "shield.checkered", "CATEGORY_SOCIAL": "person.3", "CATEGORY_MOBILE": "iphone",
    "CATEGORY_TAX": "doc.text",
    "CATEGORY_MASSAGE": "figure.mind.and.body", "CATEGORY_ACCOMMODATION": "bed.double", "CATEGORY_SALON": "scissors",
    "CATEGORY_HOSPITAL": "stethoscope", "CATEGORY_MEDICINE": "pills", "CATEGORY_TOOTH_CARE": "face.smiling",
    "CATEGORY_SUPPLIES": "bandage", "CATEGORY_EXAMINATION": "heart.text.square",
    "stuff": "shippingbox", "CATEGORY_TRANSFER": "arrow.left.arrow.right", "CATEGORY_ADJUSTMENT": "equal.circle",
}
GROUP_SYMBOLS = {
    "CATEGORY_FOOD": "fork.knife", "CATEGORY_TRANSPORT": "tram", "CATEGORY_ENTERTAINMENT": "gamecontroller",
    "CATEGORY_SHOPPING": "bag", "CATEGORY_PERSONAL": "person", "CATEGORY_MEDICAL": "cross.case",
    "CATEGORY_HOUSE": "house", "CATEGORY_FAMILY": "person.2", "CATEGORY_LIVING": "sparkles",
    "CATEGORY_INCOME": "dollarsign.circle",
}
PROJECT_SYMBOLS = {
    "PROJECT_LIVING": "house", "PROJECT_WORK": "briefcase", "holiday": "beach.umbrella", "PROJECT_TRAVEL": "airplane",
    "PROJECT_FAMILY": "person.2", "work": "graduationcap", "Claim": "arrow.uturn.left.circle",
    "Monthly Statistics": "calendar", "lunch": "fork.knife", "Dinner": "takeoutbag.and.cup.and.straw",
    "fun": "gamecontroller",
}
ACCOUNT_TYPES = {"APP_GROUP_CASH": "cash", "APP_GROUP_BANK": "bank", "APP_GROUP_CREDIT_CARD": "creditCard"}
SYSTEM_ACCOUNTS = {"RECEIVABLES_PAYABLES", "INSTALLMENT_DEBT"}


def uid(kind, moze_id):
    return str(uuid.uuid5(NAMESPACE, f"{kind}:{moze_id}")).upper()


def readable(key):
    if key in NAMES:
        return NAMES[key]
    if key.startswith("CATEGORY_"):
        return key[len("CATEGORY_"):].replace("_", " ").title()
    return key


def color(hex_argb):
    # MOZE colors are 0xAARRGGBB.
    return "#" + hex_argb[-6:].upper() if hex_argb else "#8A9099"


def iso(dt_string):
    # realmdump writes UTC ISO-8601 already; normalise to the app's decoder format.
    return dt_string.replace("+00:00", "Z")


def main(src, out):
    load = lambda name: [row for row in json.load(open(f"{src}/{name}.json")) if not row.get("isDeleted")]
    groups = {g["identifier"]: g["name"] for g in load("AHAccountGroup")}
    main_cats = {c["identifier"]: c for c in load("AHCategory")}
    classifications = {c["identifier"]: c for c in load("AHClassification")}
    records = load("AHRecord")
    now = datetime.datetime.now(datetime.timezone.utc)
    today = datetime.date.today().strftime("%Y.%m.%d")

    # Accounts
    used_accounts = collections.Counter(r["account"] for r in records)
    accounts = []
    for a in sorted(load("AHAccount"), key=lambda a: a["sequence"]):
        if a["name"] in SYSTEM_ACCOUNTS and not used_accounts[a["identifier"]]:
            continue
        group = groups.get(a["group"], "")
        kind = ACCOUNT_TYPES.get(group, "other")
        accounts.append({
            "id": uid("account", a["identifier"]),
            "name": a["name"],
            "type": kind,
            "initialBalance": a["originalAmount"],
            "creditLimit": a["creditLimit"] if kind == "creditCard" and a["creditLimit"] else None,
            # Type 0 is "day N of the month"; other deadline rules can't be expressed yet.
            "paymentDueDay": a["paymentDeadline"] if kind == "creditCard" and a["paymentDeadlineType"] == 0 else None,
            "isArchived": a["isArchived"] or group == "ARCHIVE",
            "sortOrder": a["sequence"],
        })
    account_ids = {a["id"] for a in accounts}

    # Categories: one per (MOZE subcategory, expense/income) actually used.
    usage = collections.Counter((r["classification"], r["type"]) for r in records if r["type"] in (0, 1))
    categories = {}
    for (cid, rtype), count in usage.most_common():
        c = classifications.get(cid)
        if c is None:
            continue
        kind = "expense" if rtype == 0 else "income"
        group = main_cats.get(c["category"], {})
        names = EXPENSE_NAMES if kind == "expense" else INCOME_NAMES
        categories[(cid, kind)] = {
            "id": uid(f"category-{kind}", cid),
            "name": names.get(c["name"]) or readable(c["name"]),
            "symbol": SYMBOLS.get(c["name"]) or GROUP_SYMBOLS.get(group.get("name"), "tag"),
            "colorHex": color(group.get("colorHex")),
            "kind": kind,
            "sortOrder": len(categories),
            "useCount": count,
        }

    # Projects → recurring budgets. Amount = sum of MOZE budget rows in the latest period containing today.
    budget_rows = collections.defaultdict(list)
    for b in load("AHBudget"):
        budget_rows[b["project"]].append(b)
    budgets = {}
    for p in sorted(load("AHProject"), key=lambda p: p["sequence"]):
        # Statistics projects just total everything; the app's 統計 tab covers that.
        if p["name"] == "NO_PROJECT" or p["isStatistics"]:
            continue
        rows = budget_rows[p["identifier"]]
        current = [b for b in rows if b["startDateString"][:10] <= today <= b["endDateString"][:10]]
        latest_start = max((b["startDateString"] for b in current), default=None)
        window = [b for b in current if b["startDateString"] == latest_start]
        amount = sum(b["amount"] for b in window) or None
        anchor_source = latest_start or max((b["startDateString"] for b in rows), default=p["createDateString"])
        anchor_date = datetime.datetime.strptime(anchor_source[:10], "%Y.%m.%d").date()
        weekly = p["periodUnit"] == 1
        budgets[p["identifier"]] = {
            "id": uid("budget", p["identifier"]),
            "name": readable(p["name"]),
            "symbol": PROJECT_SYMBOLS.get(p["name"], "target"),
            "amount": amount,
            "period": "weekly" if weekly else "monthly",
            # Calendar.weekday: 1 = Sunday; Python: 0 = Monday.
            "anchorDay": (anchor_date.weekday() + 1) % 7 + 1 if weekly else anchor_date.day,
            "customStart": iso(now.strftime("%Y-%m-%dT%H:%M:%SZ")),
            "customEnd": iso(now.strftime("%Y-%m-%dT%H:%M:%SZ")),
            "isPinned": amount is not None and not p["isArchived"],
            "isArchived": p["isArchived"] or not current,
            "sortOrder": p["sequence"],
        }

    # Entries
    def account_ref(moze_id):
        ref = uid("account", moze_id)
        return ref if ref in account_ids else None

    entries = []
    transfers = collections.defaultdict(list)
    for r in records:
        if r["type"] == 2 and r["transferID"]:
            transfers[r["transferID"]].append(r)
            continue
        # Type 0 = expense, 1 = income; anything else (adjustments) goes by sign.
        kind = {0: "expense", 1: "income"}.get(r["type"], "expense" if r["total"] < 0 else "income")
        cat = categories.get((r["classification"], kind))
        entries.append(entry(r, kind, abs(r["total"]), cat["id"] if cat else None,
                             account_ref(r["account"]), None, budgets.get(r["project"])))

    unpaired = 0
    for rows in transfers.values():
        out_rows = [r for r in rows if not r["isTransferIn"]]
        in_rows = [r for r in rows if r["isTransferIn"]]
        if len(out_rows) == 1 and len(in_rows) == 1:
            o, i = out_rows[0], in_rows[0]
            entries.append(entry(o, "transfer", abs(o["total"]), None, account_ref(o["account"]),
                                 account_ref(i["account"]), None, name=o["name"] or i["name"]))
        else:
            for r in rows:
                unpaired += 1
                entries.append(entry(r, "expense" if r["total"] < 0 else "income", abs(r["total"]), None,
                                     account_ref(r["account"]), None, budgets.get(r["project"])))

    backup = {
        "version": 1,
        "exportedAt": iso(now.strftime("%Y-%m-%dT%H:%M:%SZ")),
        "accounts": accounts,
        "categories": list(categories.values()),
        "budgets": list(budgets.values()),
        "entries": entries,
    }
    with open(out, "w") as f:
        json.dump(backup, f, ensure_ascii=False, indent=1)

    kinds = collections.Counter(e["kind"] for e in entries)
    print(f"accounts {len(accounts)}, categories {len(categories)}, budgets {len(budgets)}, "
          f"entries {len(entries)} {dict(kinds)}, unpaired transfer rows {unpaired}")


def entry(r, kind, amount, category_id, account_id, to_account_id, budget, name=None):
    title = name if name is not None else r["name"]
    if not title and r["store"]:
        title = r["store"]
    return {
        "id": uid("entry", r["identifier"]),
        "kind": kind,
        "amount": amount,
        "date": iso(r["date"]),
        "name": title or "",
        "note": r["desc"] or "",
        "currency": r["currency"] or "TWD",
        "createdAt": iso(r["date"]),
        "categoryID": category_id,
        "accountID": account_id,
        "toAccountID": to_account_id,
        "budgetID": budget["id"] if budget else None,
    }


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
