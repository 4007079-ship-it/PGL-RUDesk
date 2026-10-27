Name:       pgl-rudesk
Version:    1.5.1
Release:    0
Summary:    RPM package
License:    GPL-3.0
URL:        http://pgl-rudesk.ddns.info
Vendor:     SMV <4007079@gmail.com>
Conflicts:  rustdesk
Requires:   gtk3 libxcb libXfixes alsa-lib libva gstreamer1-plugins-base
Recommends: libayatana-appindicator-gtk3 libxdo
Provides:   libdesktop_drop_plugin.so()(64bit), libdesktop_multi_window_plugin.so()(64bit), libfile_selector_linux_plugin.so()(64bit), libflutter_custom_cursor_plugin.so()(64bit), libflutter_linux_gtk.so()(64bit), libscreen_retriever_plugin.so()(64bit), libtray_manager_plugin.so()(64bit), liburl_launcher_linux_plugin.so()(64bit), libwindow_manager_plugin.so()(64bit), libwindow_size_plugin.so()(64bit), libtexture_rgba_renderer_plugin.so()(64bit)

# https://docs.fedoraproject.org/en-US/packaging-guidelines/Scriptlets/

%description
PGL-RUDesk remote desktop client.

%prep
# we have no source, so nothing here

%build
# we have no source, so nothing here

# %global __python %{__python3}

%install

mkdir -p "%{buildroot}/usr/share/pgl-rudesk" && cp -r ${HBB}/flutter/build/linux/x64/release/bundle/* -t "%{buildroot}/usr/share/pgl-rudesk"
mkdir -p "%{buildroot}/usr/bin"
install -Dm 644 $HBB/res/pgl-rudesk.service -t "%{buildroot}/usr/share/pgl-rudesk/files"
install -Dm 644 $HBB/res/pgl-rudesk.desktop -t "%{buildroot}/usr/share/pgl-rudesk/files"
install -Dm 644 $HBB/res/pgl-rudesk-link.desktop -t "%{buildroot}/usr/share/pgl-rudesk/files"
install -Dm 644 $HBB/res/128x128@2x.png "%{buildroot}/usr/share/icons/hicolor/256x256/apps/pgl-rudesk.png"
install -Dm 644 $HBB/res/scalable.svg "%{buildroot}/usr/share/icons/hicolor/scalable/apps/pgl-rudesk.svg"

%files
/usr/share/pgl-rudesk/*
/usr/share/pgl-rudesk/files/pgl-rudesk.service
/usr/share/icons/hicolor/256x256/apps/pgl-rudesk.png
/usr/share/icons/hicolor/scalable/apps/pgl-rudesk.svg
/usr/share/pgl-rudesk/files/pgl-rudesk.desktop
/usr/share/pgl-rudesk/files/pgl-rudesk-link.desktop

%changelog
# let's skip this for now

%pre
# can do something for centos7
case "$1" in
  1)
    # for install
  ;;
  2)
    # for upgrade
    systemctl stop pgl-rudesk || true
  ;;
esac

%post
cp /usr/share/pgl-rudesk/files/pgl-rudesk.service /etc/systemd/system/pgl-rudesk.service
cp /usr/share/pgl-rudesk/files/pgl-rudesk.desktop /usr/share/applications/
cp /usr/share/pgl-rudesk/files/pgl-rudesk-link.desktop /usr/share/applications/
ln -sf /usr/share/pgl-rudesk/pgl-rudesk /usr/bin/pgl-rudesk
systemctl daemon-reload
systemctl enable pgl-rudesk
systemctl start pgl-rudesk
update-desktop-database

%preun
case "$1" in
  0)
    # for uninstall
    systemctl stop pgl-rudesk || true
    systemctl disable pgl-rudesk || true
    rm /etc/systemd/system/pgl-rudesk.service || true
  ;;
  1)
    # for upgrade
  ;;
esac

%postun
case "$1" in
  0)
    # for uninstall
    rm /usr/bin/pgl-rudesk || true
    rmdir /usr/lib/pgl-rudesk || true
    rmdir /usr/local/pgl-rudesk || true
    rmdir /usr/share/pgl-rudesk || true
    rm /usr/share/applications/pgl-rudesk.desktop || true
    rm /usr/share/applications/pgl-rudesk-link.desktop || true
    update-desktop-database
  ;;
  1)
    # for upgrade
    rmdir /usr/lib/pgl-rudesk || true
    rmdir /usr/local/pgl-rudesk || true
  ;;
esac
