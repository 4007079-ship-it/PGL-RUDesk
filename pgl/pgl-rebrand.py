#!/usr/bin/env python3
"""
PGL-RUDesk: патч исходников RustDesk.
Запуск из корня форка rustdesk:   python3 pgl-rebrand.py

Что делает:
  1. Название программы -> PGL-RUDesk (окна, служба, папки, тексты интерфейса)
  2. Вшивает сервер и ключ по умолчанию, включает прямой доступ по IP
  3. Переделывает окно «О программе» (ПК и телефон)
  4. Ставит иконки и логотип из папки pgl-icons (лежит рядом со скриптом)
  5. Меняет название в ярлыках, свойствах exe, Android и меню Linux
  6. Тёмная тема по умолчанию, синий акцент -> розовый #F64AF6 из логотипа
  7. Windows: при установке exe переименовывается в PGL-RUDesk.exe
  8. Регистрация по почте в окне входа (файл pgl/flutter/pgl_register.dart)
  9. Отвязка от RustDesk: без проверки обновлений, ссылки ведут на свой сайт
 10. Linux: пакет, команда, служба и папки называются pgl-rudesk
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
SITE = "http://pgl-rudesk.ddns.info"
HELP = SITE + "/help/"
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
    s.insert("direct-server".to_owned(), "Y".to_owned());
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
    for f in [f for f in ["res/rustdesk.desktop", "res/rustdesk-link.desktop",
                          "res/pgl-rudesk.desktop", "res/pgl-rudesk-link.desktop"] if Path(f).is_file()]:
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
    (r"MyTheme\.lightTheme\.primaryColor\b", "MyTheme.accent"),
    (r"Color\.fromARGB\(255, 162, 203, 241\)", "Color.fromARGB(255, 247, 190, 247)"),
    (r"Color\.fromARGB\(255, 30, 65, 98\)", "Color.fromARGB(255, 98, 30, 98)"),
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


# ---------- 7. Windows: переименование exe при первой установке ----------
def fix_windows_install():
    p = Path("src/platform/windows.rs")
    if not p.is_file():
        print("[!] src/platform/windows.rs не найден, пропущен")
        return
    src = p.read_text(encoding="utf-8")
    if "{copy_exe}\n{rename_exe}\nreg add {subkey} /f\n" in src:
        print("[=] src/platform/windows.rs: уже изменён")
        return
    a = "{copy_exe}\nreg add {subkey} /f\n"
    c = "        copy_exe = copy_exe_cmd(&src_exe, &exe, &path)?,\n        import_config = get_import_config(&exe),"
    if src.count(a) != 1 or src.count(c) != 1:
        sys.exit("[!] src/platform/windows.rs: не удалось применить исправление установки")
    src = src.replace(a, "{copy_exe}\n{rename_exe}\nreg add {subkey} /f\n").replace(
        c,
        "        copy_exe = copy_exe_cmd(&src_exe, &exe, &path)?,\n"
        "        rename_exe = rename_exe_cmd(&src_exe, &path)?,\n"
        "        import_config = get_import_config(&exe),",
    )
    p.write_text(src, encoding="utf-8")
    print("[+] src/platform/windows.rs")


# ---------- 7б. Windows: служба запускается сразу после установки ----------
def fix_windows_autostart():
    p = Path("src/platform/windows.rs")
    if not p.is_file():
        return
    src = p.read_text(encoding="utf-8")
    line = '    Config::set_option("stop-service".into(), "".into());\n\n    let tray_shortcuts'
    if line in src:
        print("[=] Автозапуск службы: уже включён")
        return
    a = '        Config::set_option("api-server".into(), lic.api);\n    }\n\n    let tray_shortcuts'
    if src.count(a) != 1:
        sys.exit("[!] src/platform/windows.rs: не удалось включить автозапуск службы")
    src = src.replace(a, '        Config::set_option("api-server".into(), lic.api);\n    }\n'
                      '    // A stale "stop-service" left by a portable run would skip creating the service.\n'
                      + line)
    p.write_text(src, encoding="utf-8")
    print("[+] Автозапуск службы после установки")


# ---------- 9. Отвязка от RustDesk ----------
UNLINK = {
    "src/common.rs": [
        ("pub async fn do_check_software_update() -> hbb_common::ResultType<()> {\n",
         "pub async fn do_check_software_update() -> hbb_common::ResultType<()> {\n"
         "    if is_custom_client() {\n        return Ok(());\n    }\n"),
        ("    drop(s);\n    // тёмная тема",
         "    drop(s);\n    *config::PROD_RENDEZVOUS_SERVER.write().unwrap() = \"" + SERVER + "\".to_owned();\n"
         "    // тёмная тема"),
    ],
    "src/client.rs": [
        ('"https://rustdesk.com/docs/en/manual/linux/#x11-required"', '"' + HELP + '#x11"'),
        ('"https://rustdesk.com/docs/en/manual/linux/#login-screen"', '"' + HELP + '#login-screen"'),
    ],
    "src/lang/en.rs": [
        ('"https://rustdesk.com/docs/en/client/linux/#x11-required"', '"' + HELP + '#x11"'),
        ('"https://rustdesk.com/docs/en/client/mac/#enable-permissions"', '"' + HELP + '#mac-permissions"'),
    ],
    "flutter/lib/desktop/pages/connection_page.dart": [
        ('"https://rustdesk.com/pricing"', '"' + SITE + '/"'),
    ],
    "flutter/lib/desktop/pages/install_page.dart": [
        ("'https://rustdesk.com/privacy.html'", "'" + HELP + "#privacy'"),
    ],
    "flutter/lib/desktop/pages/desktop_home_page.dart": [
        ("'https://rustdesk.com/download'", "'" + SITE + "/#download'"),
        ("'https://github.com/rustdesk/rustdesk/releases/tag/${bind.mainGetNewVersion()}'",
         "'https://github.com/4007079-ship-it/PGL-RUDesk/releases/tag/pgl-rudesk'"),
        ("'https://rustdesk.com/docs/en/client/linux/#permissions-issue'", "'" + HELP + "#selinux'"),
        ("'https://rustdesk.com/docs/en/client/linux/#x11-required'", "'" + HELP + "#x11'"),
        ("'https://rustdesk.com/docs/en/client/linux/#login-screen'", "'" + HELP + "#login-screen'"),
    ],
    "flutter/lib/desktop/pages/desktop_setting_page.dart": [
        ("final showAutoUpdate = (isWindows && bind.mainIsInstalled()) ||",
         "final showAutoUpdate = (isWindows && bind.mainIsInstalled() && !bind.isCustomClient()) ||"),
    ],
    "flutter/lib/common/widgets/toolbar.dart": [
        ("'https://github.com/rustdesk/rustdesk/issues/14586'", "'" + HELP + "#wayland-keyboard'"),
    ],
    "flutter/lib/mobile/pages/settings_page.dart": [
        ("const url = 'https://rustdesk.com/';", "const url = '" + SITE + "/';"),
        ("child: Text('rustdesk.com',", "child: Text('" + SITE.split('//')[1] + "',"),
        ("launchUrlString('https://rustdesk.com/privacy.html')", "launchUrlString('" + HELP + "#privacy')"),
    ],
    "flutter/lib/mobile/pages/connection_page.dart": [
        ("'https://rustdesk.com/download'", "'" + SITE + "/#download'"),
    ],
}


def unlink_rustdesk():
    changed = 0
    for path, pairs in UNLINK.items():
        p = Path(path)
        src = p.read_text(encoding="utf-8")
        new = src
        for a, b in pairs:
            if b in new:
                continue
            n = new.count(a)
            if n == 0:
                sys.exit(f"[!] {path}: не найдено: {a[:60]}")
            new = new.replace(a, b)
        if new != src:
            p.write_text(new, encoding="utf-8")
            changed += 1
    print(f"[+] Отвязка от RustDesk: изменено файлов {changed}" if changed else "[=] Отвязка от RustDesk: уже сделана")


# ---------- 10. Linux: пакет, команда, служба и папки называются pgl-rudesk ----------
LINUX_NAME = "pgl-rudesk"
FLATPAK_ID = "com.pglrudesk.PGLRUDesk"
# «rustdesk» как отдельное имя; не трогаем librustdesk, rustdesk_core_main, rustdesk.com,
# rustdesk-org, github.com/rustdesk, com.rustdesk.* и имя rustdesk.deb (файл между шагами сборки)
LINUX_TOKEN = re.compile(
    r"(?<![\w.\-])(?<!github\.com/)(?<!github\.com/rustdesk/)rustdesk(?![\w]|\.com|-org|\.deb)"
)
LINUX_FILES = [
    "res/DEBIAN/postinst", "res/DEBIAN/preinst", "res/DEBIAN/prerm", "res/DEBIAN/postrm",
    "res/rpm-flutter.spec", "res/rpm-flutter-suse.spec", "res/PKGBUILD", "res/pacman_install",
    "appimage/AppImageBuilder-x86_64.yml", "appimage/AppImageBuilder-aarch64.yml",
    "flatpak/rustdesk.json",
]
LINUX_RENAMES = [
    ("res/rustdesk.service", "res/pgl-rudesk.service"),
    ("res/rustdesk.desktop", "res/pgl-rudesk.desktop"),
    ("res/rustdesk-link.desktop", "res/pgl-rudesk-link.desktop"),
    ("flatpak/com.rustdesk.RustDesk.metainfo.xml", f"flatpak/{FLATPAK_ID}.metainfo.xml"),
]
BUILD_PY_FUNCS = [
    "generate_control_file", "stage_libdrmtap_into_deb", "measured_glibc_floor",
    "retarget_control_to_drm_variant", "build_flutter_deb", "assert_staged_binary_is_drm",
    "build_deb_from_folder",
]
RPM_META = [
    ("URL:        https://rustdesk.com", f"URL:        {SITE}"),
    ("Vendor:     rustdesk <info@rustdesk.com>", f"Vendor:     {AUTHOR} <{EMAIL}>"),
    ("The best open-source remote desktop client software, written in Rust.",
     "PGL-RUDesk remote desktop client."),
]
FLATPAK_METAINFO = f"""<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>{FLATPAK_ID}</id>
  <developer id="com.pglrudesk">
    <name>{AUTHOR}</name>
  </developer>
  <launchable type="desktop-id">{FLATPAK_ID}.desktop</launchable>
  <metadata_license>CC0-1.0</metadata_license>
  <project_license>AGPL-3.0-only</project_license>
  <name>{APP_NAME}</name>
  <summary>Remote desktop access through your own server</summary>
  <description>
    <p>{APP_NAME} connects to computers and phones through its own server: screen, mouse, keyboard and files, encrypted end to end.</p>
    <p>Based on RustDesk (AGPL-3.0).</p>
  </description>
  <categories>
    <category>Utility</category>
  </categories>
  <url type="homepage">{SITE}</url>
  <url type="help">{HELP}</url>
  <url type="vcs-browser">https://github.com/4007079-ship-it/PGL-RUDesk</url>
  <content_rating type="oars-1.1" />
</component>
"""


def _linux_sub(text):
    return LINUX_TOKEN.sub(LINUX_NAME, text)


def _build_py_linux(src):
    lines = src.split("\n")
    out, inside = [], False
    for line in lines:
        m = re.match(r"def (\w+)\(", line)
        if m:
            inside = m.group(1) in BUILD_PY_FUNCS
        elif line and not line[0].isspace():
            inside = False
        keep = (line.lstrip().startswith("#") or "rustdesk.deb" in line
                or "rustdesk-%s.deb" in line)
        if line.startswith("DRM_PACKAGE_NAME =") or line.startswith("DRMTAP_DLOPEN_MARKER ="):
            line = _linux_sub(line)
        elif inside and not keep:
            line = _linux_sub(line)
        out.append(line)
    src = "\n".join(out)
    # Описание пакета и замена старого пакета rustdesk (прошлые сборки PGL-RUDesk назывались так)
    src = src.replace(
        "Maintainer: rustdesk <info@rustdesk.com>\nHomepage: https://rustdesk.com\n",
        f"Maintainer: {AUTHOR} <{EMAIL}>\nHomepage: {SITE}\nConflicts: rustdesk\nReplaces: rustdesk\n")
    src = src.replace("Description: A remote control software.\n",
                      f"Description: {APP_NAME} remote desktop client.\n")
    src = src.replace(
        f"            out.append('Conflicts: {LINUX_NAME}\\nReplaces: {LINUX_NAME}\\nProvides: {LINUX_NAME}\\n')\n",
        f"            out.append('Conflicts: {LINUX_NAME}, rustdesk\\nReplaces: {LINUX_NAME}, rustdesk\\nProvides: {LINUX_NAME}\\n')\n"
        "        elif line.startswith('Conflicts:') or line.startswith('Replaces:'):\n"
        "            continue\n")
    return src


def rename_linux():
    if f'set(BINARY_NAME "{LINUX_NAME}")' in Path("flutter/linux/CMakeLists.txt").read_text(encoding="utf-8"):
        print("[=] Linux-имена: уже изменены")
        return
    changed = []
    for old, new in LINUX_RENAMES:
        if Path(old).exists() and not Path(new).exists():
            Path(old).rename(new)
            changed.append(new)
    for f in ["res/pgl-rudesk.service", "res/pgl-rudesk.desktop", "res/pgl-rudesk-link.desktop"] + LINUX_FILES:
        p = Path(f)
        src = p.read_text(encoding="utf-8")
        new = src
        for a, b in RPM_META:
            new = new.replace(a, b)
        new = _linux_sub(new)
        if f.endswith(".spec"):
            new = new.replace("Requires:   ", "Conflicts:  rustdesk\nRequires:   ", 1)
        if f == "res/PKGBUILD":
            new = new.replace("conflicts=()", "conflicts=('rustdesk')")
        if f == "res/pgl-rudesk.service":
            new = new.replace("Description=RustDesk", f"Description={APP_NAME}")
        if f == "flatpak/rustdesk.json":
            new = new.replace('"com.rustdesk.RustDesk"', f'"{FLATPAK_ID}"').replace(
                '"com.rustdesk.RustDesk.metainfo.xml"', f'"{FLATPAK_ID}.metainfo.xml"')
        if new != src:
            p.write_text(new, encoding="utf-8")
            changed.append(f)
    meta = Path(f"flatpak/{FLATPAK_ID}.metainfo.xml")
    if meta.read_text(encoding="utf-8") != FLATPAK_METAINFO:
        meta.write_text(FLATPAK_METAINFO, encoding="utf-8")
        changed.append(str(meta))
    for f, pairs in {
        "build.py": None,
        "flutter/linux/CMakeLists.txt": [('set(BINARY_NAME "rustdesk")', f'set(BINARY_NAME "{LINUX_NAME}")')],
        "libs/scrap/src/common/drmtap_dl.rs": [('"/usr/lib/rustdesk/libdrmtap.so.0"', f'"/usr/lib/{LINUX_NAME}/libdrmtap.so.0"')],
    }.items():
        p = Path(f)
        src = p.read_text(encoding="utf-8")
        if pairs is None:
            new = _build_py_linux(src)
        else:
            new = src
            for a, b in pairs:
                new = new.replace(a, b)
        if new != src:
            p.write_text(new, encoding="utf-8")
            changed.append(f)
    print(f"[+] Linux-имена: изменено {len(changed)}" if changed else "[=] Linux-имена: уже изменены")

# ---------- 8. Регистрация по почте в окне входа ----------
def accounts():
    import shutil
    src_file = Path(__file__).resolve().parent / "flutter" / "pgl_register.dart"
    if not src_file.is_file():
        print("[!] pgl/flutter/pgl_register.dart не найден — регистрация не добавлена")
        return
    shutil.copyfile(src_file, "flutter/lib/common/widgets/pgl_register.dart")
    print("[+] flutter/lib/common/widgets/pgl_register.dart")

    p = Path("flutter/lib/common/widgets/login.dart")
    s = p.read_text(encoding="utf-8")
    if "pglRegisterDialog" in s:
        print(f"[=] {p}: уже изменён")
    else:
        reps = [
            ("import './oidc_auth_status.dart';\n",
             "import './oidc_auth_status.dart';\nimport './pgl_register.dart';\n"),
            ("                title: translate(DialogTextField.kUsernameTitle),\n                controller: username,",
             "                title: 'Почта',\n                controller: username,"),
            ("        setState(() => usernameMsg = translate('Username missed'));",
             "        setState(() => usernameMsg = 'Введите почту');"),
            ("            userFocusNode: userFocusNode,\n          ),\n          thirdAuthWidget(),",
             "            userFocusNode: userFocusNode,\n          ),\n"
             "          TextButton(\n"
             "            onPressed: isInProgress\n"
             "                ? null\n"
             "                : () async {\n"
             "                    final reg = await pglRegisterDialog();\n"
             "                    if (reg != null) {\n"
             "                      username.text = reg.email;\n"
             "                      password.text = reg.password;\n"
             "                      await onLogin();\n"
             "                    }\n"
             "                  },\n"
             "            child: Text('Нет аккаунта? Регистрация',\n"
             "                style: TextStyle(color: MyTheme.accent)),\n"
             "          ).marginOnly(top: 8),\n"
             "          thirdAuthWidget(),"),
        ]
        for a, b in reps:
            if s.count(a) != 1:
                sys.exit(f"[!] {p}: не удалось добавить регистрацию")
            s = s.replace(a, b)
        p.write_text(s, encoding="utf-8")
        print(f"[+] {p}")

    p = Path("flutter/lib/models/user_model.dart")
    s = p.read_text(encoding="utf-8")
    a = "        return jsonDecode(item.substring('common-oidc/'.length));\n"
    if a in s:
        p.write_text(s.replace(a, a.replace("));\n", ")) ?? [];\n")), encoding="utf-8")
        print(f"[+] {p}")
    else:
        print(f"[=] {p}: уже изменён")


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
fix_windows_install()
fix_windows_autostart()
accounts()
unlink_rustdesk()
rename_linux()
print(f"\nГотово: {APP_NAME}, сервер {SERVER}, автор {AUTHOR} <{EMAIL}>")
