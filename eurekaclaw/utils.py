import shutil
import pathlib

def copy_file(src, dst, overwrite=False):
    filename =pathlib.Path(src).name
    dst = pathlib.Path(dst) / filename
    if dst.exists():
        if not overwrite:
            return False
        if dst.is_dir():
            shutil.rmtree(dst)
        else:
            dst.unlink()
    shutil.copy2(src, dst)
    return True

def copy_directory(src, dst, overwrite=False):
    src = pathlib.Path(src)
    dst = pathlib.Path(dst) / src.name
    if dst.exists():
        if not overwrite:
            return False
        if dst.is_dir():
            shutil.rmtree(dst)
        else:
            dst.unlink()
    shutil.copytree(src, dst)
    return True