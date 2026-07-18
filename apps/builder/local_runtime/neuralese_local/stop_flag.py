from __future__ import annotations

import os
from pathlib import Path
from typing import Callable, List


class StopFlag:
    def __init__(self, path: str | Path, parent_pid: int | None = None):
        self.path = Path(path)
        self.parent_pid = int(parent_pid or 0)
        self._callbacks: List[Callable[[], None]] = []
        self._seen = False

    @property
    def closed(self) -> bool:
        return self.requested()

    def on_kill(self, callback: Callable[[], None]) -> None:
        self._callbacks.append(callback)

    def requested(self) -> bool:
        exists = self.path.exists() or self._parent_dead()
        if exists and not self._seen:
            self._seen = True
            for cb in list(self._callbacks):
                cb()
        return exists

    def _parent_dead(self) -> bool:
        if self.parent_pid <= 0:
            return False
        if self.parent_pid == os.getpid():
            return False
        if os.name == "nt":
            return not _windows_pid_alive(self.parent_pid)
        try:
            os.kill(self.parent_pid, 0)
            return False
        except ProcessLookupError:
            return True
        except PermissionError:
            return False
        except Exception:
            return False


def _windows_pid_alive(pid: int) -> bool:
    try:
        import ctypes
        from ctypes import wintypes

        process_query_limited_information = 0x1000
        still_active = 259
        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
        kernel32.OpenProcess.restype = wintypes.HANDLE
        kernel32.GetExitCodeProcess.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]
        kernel32.GetExitCodeProcess.restype = wintypes.BOOL
        kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
        kernel32.CloseHandle.restype = wintypes.BOOL
        handle = kernel32.OpenProcess(process_query_limited_information, False, wintypes.DWORD(pid))
        if not handle:
            return False
        try:
            exit_code = wintypes.DWORD()
            if not kernel32.GetExitCodeProcess(handle, ctypes.byref(exit_code)):
                return False
            return int(exit_code.value) == still_active
        finally:
            kernel32.CloseHandle(handle)
    except Exception:
        return False
