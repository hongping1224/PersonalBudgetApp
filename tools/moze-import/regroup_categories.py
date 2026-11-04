"""Rewrite a copy of the app's SwiftData store so expenses use a few broad categories.

Usage: python3 regroup_categories.py <default.store> <moze-backup.json>

Entries restored from the first MOZE conversion lost their category (fixed in
moze_to_backup.py); their original category is looked up in the regenerated backup by entry ID.
Expense categories are then merged into 食物 / 玩樂 / 家庭 / 個人 / 交通 / 其他; income is left as is.
Safe to run again on an already regrouped store.
"""
import collections
import json
import sqlite3
import sys
import uuid

GROUPS = {
    "食物": ["午餐", "晚餐", "早餐", "點心", "飲料", "咖啡", "水果"],
    "玩樂": ["遊戲", "電影", "音樂", "影音", "訂閱", "遊樂園", "展覽", "博弈", "休閒", "住宿", "機票", "社交"],
    "家庭": ["超市", "日用品", "房租", "管理費", "水費", "電費", "瓦斯", "網路", "家具", "家電", "修繕",
             "洗衣", "cleaning", "照護"],
    "個人": ["衣服", "鞋子", "包包", "配件", "理髮", "美容", "按摩", "看醫生", "牙齒保健", "藥品",
             "醫療用品", "健康檢查", "手機", "電話費", "3C"],
    "交通": ["機車", "高鐵", "計程車", "捷運", "火車", "加油", "汽車", "腳踏車", "停車"],
    "保險": ["保險"],
}
TARGET = {old: new for new, olds in GROUPS.items() for old in olds}
# New categories in display order: existing row reused for it (keeps its ID), symbol, color.
KEEP = {
    "食物": ("午餐", "fork.knife", "#E9C98F"),
    "玩樂": ("遊戲", "gamecontroller", "#8E7CC3"),
    "家庭": ("房租", "house", "#D9706F"),
    "個人": ("衣服", "person", "#4A90E2"),
    "交通": ("機車", "scooter", "#5BA4A4"),
    "保險": ("保險", "shield.checkered", "#7A8B5C"),
    "其他": ("其他", "ellipsis", "#6C5FA7"),
}


def insert_category(db):
    """Adds an empty EntryCategory row, keeping Core Data's primary key counter in step."""
    ent, last = db.execute("select Z_ENT, Z_MAX from Z_PRIMARYKEY where Z_NAME='EntryCategory'").fetchone()
    pk = last + 1
    db.execute("update Z_PRIMARYKEY set Z_MAX=? where Z_ENT=?", (pk, ent))
    db.execute("insert into ZENTRYCATEGORY (Z_PK, Z_ENT, Z_OPT, ZSORTORDER, ZUSECOUNT, ZKINDRAW, ZNAME, ZSYMBOL, "
               "ZCOLORHEX, ZID) values (?, ?, 1, 0, 0, 'expense', '', 'tag', '#000000', ?)",
               (pk, ent, uuid.uuid4().bytes))
    return pk


def main(store, backup_path):
    backup = json.load(open(backup_path))
    cat_names = {c["id"]: (c["name"], c["kind"]) for c in backup["categories"]}
    original = {e["id"]: cat_names[e["categoryID"]] for e in backup["entries"] if e["categoryID"]}

    db = sqlite3.connect(store)
    db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    cats = {pk: (name, kind) for pk, name, kind in db.execute("select Z_PK, ZNAME, ZKINDRAW from ZENTRYCATEGORY")}
    by_name = {(name, kind): pk for pk, (name, kind) in cats.items()}

    keep_pk = {}
    for order, (new, (old, symbol, color)) in enumerate(KEEP.items()):
        pk = by_name.get((new, "expense")) or by_name.get((old, "expense")) or insert_category(db)
        db.execute("update ZENTRYCATEGORY set ZNAME=?, ZSYMBOL=?, ZCOLORHEX=?, ZSORTORDER=? where Z_PK=?",
                   (new, symbol, color, order, pk))
        keep_pk[new] = pk

    moved = collections.Counter()
    unknown = collections.Counter()
    for pk, eid, kind, cat in db.execute("select Z_PK, ZID, ZKINDRAW, ZCATEGORY from ZENTRY").fetchall():
        if kind == "transfer":
            continue
        # The MOZE category wins, so a rerun can split an earlier merge further.
        name = original.get(str(uuid.UUID(bytes=eid)).upper(), (None,))[0] or (cats[cat][0] if cat else None)
        if name is None:
            unknown[kind] += 1
            continue
        if kind == "income":
            new_pk = by_name.get((name, "income"))
            label = name
        else:
            label = name if name in KEEP else TARGET.get(name, "其他")
            new_pk = keep_pk[label]
        if new_pk != cat:
            db.execute("update ZENTRY set ZCATEGORY=? where Z_PK=?", (new_pk, pk))
        moved[(kind, name, label)] += 1

    kept = set(keep_pk.values())
    for pk, (name, kind) in cats.items():
        if kind == "expense" and pk not in kept:
            db.execute("delete from ZENTRYCATEGORY where Z_PK=?", (pk,))
    db.execute("update ZENTRYCATEGORY set ZUSECOUNT=(select count(*) from ZENTRY where ZCATEGORY=ZENTRYCATEGORY.Z_PK)")
    db.commit()
    db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    db.close()

    summary = collections.defaultdict(list)
    for (kind, name, label), n in sorted(moved.items(), key=lambda x: -x[1]):
        summary[(kind, label)].append(f"{name} {n}")
    for (kind, label), items in sorted(summary.items()):
        print(f"{kind} {label}: " + "、".join(items))
    print("no category found:", dict(unknown))


if __name__ == "__main__":
    main(*sys.argv[1:3])
