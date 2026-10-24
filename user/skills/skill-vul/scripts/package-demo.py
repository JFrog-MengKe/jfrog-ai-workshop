"""仅用标准库构建扫描 ZIP；不导入或运行被扫描代码。"""
from pathlib import Path
import hashlib
import zipfile


def main():
    root = Path(__file__).resolve().parents[1]
    files = [root / "SKILL.md", root / "requirements.txt"]
    for folder in ("scripts", "references", "fixtures"):
        files.extend(p for p in (root / folder).rglob("*")
                     if p.is_file() and "__pycache__" not in p.parts and p.suffix != ".pyc")
    destination = root / "dist" / "skill-vul-1.0.0.zip"
    destination.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(files):
            if path.is_symlink():
                raise ValueError(f"不打包符号链接：{path}")
            info = zipfile.ZipInfo(path.relative_to(root).as_posix(), (2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, path.read_bytes())
    with zipfile.ZipFile(destination) as archive:
        assert "SKILL.md" in archive.namelist()
        assert archive.testzip() is None
    digest = hashlib.sha256(destination.read_bytes()).hexdigest()
    destination.with_suffix(".zip.sha256").write_text(f"{digest}  {destination.name}\n")
    print(f"Created: {destination}\nFiles: {len(files)}\nSHA256: {digest}")


if __name__ == "__main__":
    main()
