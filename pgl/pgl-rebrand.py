#!/usr/bin/env python3
"""
PGL-RUDesk: патч исходников RustDesk.
Запуск из корня форка rustdesk:   python3 pgl-rebrand.py

Что делает:
  1. Название программы -> PGL-RUDesk (окна, служба, папки, тексты интерфейса)
  2. Вшивает сервер и ключ по умолчанию
  3. Переделывает окно «О программе» (ПК и телефон)
  4. Ставит иконки и логотип из папки pgl-icons (лежит рядом со скриптом)
  5. Меняет название в ярлыках, свойствах exe, Android и меню Linux
  6. Тёмная тема по умолчанию, синий акцент -> розовый #F64AF6 из логотипа
Повторный запуск безопасен: уже применённые изменения пропускаются.
"""
import re
import sys
from pathlib import Path

APP_NAME = "PGL-RUDesk"
SERVER = "157.228.187.7"
KEY = "CClcO0EUUWXSZa23Svb6wND2A6MOVjudEpohFXpJ4pw="
AUTHOR = "SMV"
EMAIL = "4007079@gmail.com"
FOOTNOTE = "На основе RustDesk © Purslane Tech Pte. Ltd. · Лицензия AGPL-3.0"

MARK = "PGL-RUDesk patch"


def patch(path, func):
    p = Path(path)
    if not p.is_file():
        sys.exit(f"Не найден файл {path}. Запускайте скрипт из корня репозитория rustdesk.")
    src = p.read_text(encoding="utf-8")
    if MARK in src:
        print(f"[=] {path}: уже изменён")
        return
    new = func(src)
    if new == src:
        sys.exit(f"[!] {path}: не удалось применить изменение (код RustDesk поменялся?)")
    p.write_text(new, encoding="utf-8")
    print(f"[+] {path}")


# ---------- 1-2. Rust: имя, сервер, ключ ----------
def rust(src):
    func = f'''
// {MARK}: название, сервер и ключ по умолчанию
pub fn apply_pgl_branding() {{
    *config::APP_NAME.write().unwrap() = "{APP_NAME}".to_owned();
    let mut s = config::DEFAULT_SETTINGS.write().unwrap();
    s.insert("custom-rendezvous-server".to_owned(), "{SERVER}".to_owned());
    s.insert("key".to_owned(), "{KEY}".to_owned());
    drop(s);
    // тёмная тема по умолчанию (пользователь может переключить)
    config::DEFAULT_LOCAL_SETTINGS
        .write()
        .unwrap()
        .insert("theme".to_owned(), "dark".to_owned());
}}

pub fn load_custom_client() {{
    apply_pgl_branding();'''
    src = src.replace("\npub fn load_custom_client() {", func, 1)
    src = src.replace(
        "pub fn read_custom_client(config: &str) {",
        "pub fn read_custom_client(config: &str) {\n    apply_pgl_branding();",
        1,
    )
    return src


# ---------- 3a. Окно «О программе» на ПК ----------
def desktop(src):
    new_block = f"""              // {MARK}: автор и контакты
              SelectionArea(
                  child: Text('Автор: {AUTHOR}')
                      .marginSymmetric(vertical: 4.0)),
              InkWell(
                  onTap: () {{
                    launchUrlString('mailto:{EMAIL}');
                  }},
                  child: Text(
                    'Почта: {EMAIL}',
                    style: linkStyle,
                  ).marginSymmetric(vertical: 4.0)),
              const SizedBox(height: 24.0),
              SelectionArea(
                  child: Text(
                '{FOOTNOTE}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              )).marginSymmetric(vertical: 4.0)
            ],
          ).marginOnly(left: _kContentHMargin)"""
    pattern = re.compile(
        r"              InkWell\(\n\s+onTap: \(\) \{\n\s+launchUrlString\('https://rustdesk\.com/privacy\.html'\);"
        r".*?\).marginSymmetric\(vertical: 4\.0\)\n            \],\n          \)\.marginOnly\(left: _kContentHMargin\)",
        re.S,
    )
    return pattern.sub(lambda _: new_block, src, count=1)


# ---------- 3b. Окно «О программе» на телефоне ----------
def mobile(src):
    new_block = f"""      content: Wrap(direction: Axis.vertical, spacing: 12, children: [
        // {MARK}: автор и контакты
        Text('Version: $version'),
        Text('Автор: {AUTHOR}'),
        InkWell(
            onTap: () async {{
              await launchUrl(Uri.parse('mailto:{EMAIL}'));
            }},
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('{EMAIL}',
                  style: TextStyle(
                    decoration: TextDecoration.underline,
                  )),
            )),
        Text('{FOOTNOTE}',
            style: TextStyle(fontSize: 11, color: Colors.grey)),
      ]),"""
    pattern = re.compile(
        r"      content: Wrap\(direction: Axis\.vertical, spacing: 12, children: \[\n"
        r"        Text\('Version: \$version'\),.*?rustdesk\.com',.*?\)\),\n      \]\),",
        re.S,
    )
    return pattern.sub(lambda _: new_block, src, count=1)


# ---------- 5. Название в файлах сборки (ярлыки, свойства exe, Android) ----------
ANDROID_ID = "com.pgl.rudesk"  # своё имя пакета: ставится рядом с обычным RustDesk


def rename(path, pairs):
    p = Path(path)
    if not p.is_file():
        print(f"[!] {path}: не найден, пропущен")
        return
    src = p.read_text(encoding="utf-8")
    new = src
    for old, repl in pairs:
        new = new.replace(old, repl)
    if new != src:
        p.write_text(new, encoding="utf-8")
        print(f"[+] {path}")
    else:
        print(f"[=] {path}: уже изменён")


def rename_all():
    # Windows: «Описание» и «Продукт» в свойствах exe и в диспетчере задач
    rename("flutter/windows/runner/Runner.rc", [
        ('"RustDesk Remote Desktop"', f'"{APP_NAME} Remote Desktop"'),
        ('VALUE "ProductName", "RustDesk"', f'VALUE "ProductName", "{APP_NAME}"'),
    ])
    # Android: название под иконкой, служба управления, тексты
    rename("flutter/android/app/src/main/AndroidManifest.xml", [
        ('android:label="RustDesk"', f'android:label="{APP_NAME}"'),
        ('android:label="RustDesk Input"', f'android:label="{APP_NAME} Input"'),
    ])
    for f in sorted(Path("flutter/android/app/src/main/res").glob("values*/strings.xml")):
        src = f.read_text(encoding="utf-8")
        if "RustDesk" in src:
            f.write_text(src.replace("RustDesk", APP_NAME), encoding="utf-8")
            print(f"[+] {f}")
    rename("flutter/android/app/build.gradle", [
        ('applicationId "com.carriez.flutter_hbb"', f'applicationId "{ANDROID_ID}"'),
    ])
    # Linux: название в меню приложений
    for f in ["res/rustdesk.desktop", "res/rustdesk-link.desktop"]:
        rename(f, [("\nName=RustDesk\n", f"\nName={APP_NAME}\n")])


# ---------- 6. Цвета: синий акцент -> розовый из логотипа ----------
PINK = "F64AF6"
COLOR_MAP = {  # синий RustDesk -> оттенок розового (альфа-канал сохраняется)
    "0071FF": PINK,      # основной акцент
    "2C8CFF": PINK,      # кнопки
    "0697EA": PINK,      # заголовок окна
    "0583EA": "DD42DD",
    "0C6AF6": "C93AC9",  # боковая панель
    "00B6F0": "F87CF8",  # цвет ID (светлее для читаемости)
    "00BFE1": "F98EF9",  # градиент на странице подключения
    "2F65BA": "A8329F",  # рамка
}
NAMED = [  # Colors.blue* -> конкретные цвета
    (r"Colors\.blue\.shade300\b", "Color(0xFFFA8CFA)"),
    (r"Colors\.blue\.shade800\b", "Color(0xFFB02FB0)"),
    (r"Colors\.blueAccent\b", f"Color(0xFF{PINK})"),
    (r"Colors\.blue\b(?!\.shade)", f"Color(0xFF{PINK})"),
]


def recolor():
    hex_re = re.compile(r"0x([0-9A-Fa-f]{2})(" + "|".join(COLOR_MAP) + r")\b", re.I)
    changed = 0
    for f in sorted(Path("flutter/lib").rglob("*.dart")):
        src = f.read_text(encoding="utf-8")
        lines = src.split("\n")
        for i, line in enumerate(lines):
            if '"blue":' in line:  # цвета меток, которые выбирает пользователь
                continue
            line = hex_re.sub(lambda m: "0x" + m.group(1).upper() + COLOR_MAP[m.group(2).upper()], line)
            for pat, repl in NAMED:
                line = re.sub(pat, repl, line)
            lines[i] = line
        new = "\n".join(lines)
        if new != src:
            f.write_text(new, encoding="utf-8")
            changed += 1
    print(f"[+] Цвета: изменено файлов {changed}" if changed else "[=] Цвета: уже изменены")


# ---------- 4. Иконки и логотип ----------
def install_icons():
    icons = Path(__file__).resolve().parent / "pgl-icons"
    if not icons.is_dir():
        print("[!] Папка pgl-icons не найдена рядом со скриптом — иконки не заменены")
        return
    import shutil
    n = 0
    for f in icons.rglob("*"):
        if f.is_file():
            dst = Path(f.relative_to(icons))
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(f, dst)
            n += 1
    # фон адаптивной иконки Android — чёрный, как у логотипа
    bg = Path("flutter/android/app/src/main/res/values/ic_launcher_background.xml")
    if bg.is_file():
        bg.write_text(bg.read_text(encoding="utf-8").replace("#ffffff", "#000000").replace("#FFFFFF", "#000000"),
                      encoding="utf-8")
    print(f"[+] Иконки: заменено файлов {n}")


patch("src/common.rs", rust)
patch("flutter/lib/desktop/pages/desktop_setting_page.dart", desktop)
patch("flutter/lib/mobile/pages/settings_page.dart", mobile)
install_icons()
rename_all()
recolor()
print(f"\nГотово: {APP_NAME}, сервер {SERVER}, автор {AUTHOR} <{EMAIL}>")
