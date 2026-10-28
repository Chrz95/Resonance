"""Install committed icon assets after Flutter regenerates platform runners."""
from pathlib import Path
import shutil


def install_branding(client: Path):
    source = client / 'platform_config' / 'icons'
    resource = client / 'windows' / 'runner' / 'resources' / 'app_icon.ico'
    resource.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source / 'windows' / 'app_icon.ico', resource)
    shutil.copytree(source / 'android', client / 'android' / 'app' / 'src' / 'main' / 'res', dirs_exist_ok=True)
