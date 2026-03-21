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