"""After flutter create, apply project branding and required Android network permission."""
from pathlib import Path
import shutil

root = Path(__file__).resolve().parents[1]
manifest = root / 'android/app/src/main/AndroidManifest.xml'
s = manifest.read_text(encoding='utf-8')
if 'android.permission.INTERNET' not in s:
    s = s.replace('<application', '<uses-permission android:name="android.permission.INTERNET"/>\n    <application', 1)
if 'android:usesCleartextTraffic=' not in s:
    s = s.replace('<application', '<application android:usesCleartextTraffic="true"', 1)
# Cleartext HTTP remains limited to private IPv4 LAN addresses by the app.
# No screen sharing or input control is allowed over this transport.
s = s.replace('android:label="controle_pc_distance"', 'android:label="Controle PC Distance"')
manifest.write_text(s, encoding='utf-8')
for density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']:
    source = root / 'branding/android' / density / 'ic_launcher.png'
    dest = root / 'android/app/src/main/res' / ('mipmap-' + density) / 'ic_launcher.png'
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, dest)
ico = root / 'windows/runner/resources/app_icon.ico'
if ico.parent.exists():
    shutil.copyfile(root / 'branding/app_icon.ico', ico)
# Flutter's generated template test imports MyApp, which is not part of this app.
template_test = root / 'test/widget_test.dart'
if template_test.exists():
    template_test.unlink()
print('Android permission, launcher icons and Windows icon ready')
