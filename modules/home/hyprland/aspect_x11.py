"""Read-only, event-driven MultiViewer aspect metadata from X11."""

import contextlib
import math
import sys
from fractions import Fraction

from Xlib import X, Xatom, Xutil, display, error


class AspectHints:
    """Watch all clients so late WM_CLASS and aspect hints are observed.

    Connection/display errors propagate to the caller. Vanished clients and
    malformed or missing metadata are treated as absent aspect hints.
    """

    def __init__(self):
        # python-xlib prints authentication diagnostics to stdout. Keep them
        # visible on stderr without corrupting the controller's JSON output.
        with contextlib.redirect_stdout(sys.stderr):
            self._display = display.Display()
        try:
            self._root = self._display.screen().root
            self._client_list = self._display.intern_atom("_NET_CLIENT_LIST")
            self._pid = self._display.intern_atom("_NET_WM_PID")
            self._name = self._display.intern_atom("_NET_WM_NAME")
            self._utf8 = self._display.intern_atom("UTF8_STRING")
            self._properties = {
                self._pid,
                self._name,
                Xatom.WM_NAME,
                Xatom.WM_CLASS,
                Xatom.WM_NORMAL_HINTS,
            }
            self._windows = {}
            self._metadata = {}
            self._ratios = {}
            caught = error.CatchError()
            self._root.change_attributes(
                event_mask=X.PropertyChangeMask, onerror=caught
            )
            self._display.sync()
            if caught.get_error() is not None:
                raise caught.get_error()
        except Exception:
            self._display.close()
            raise

    def fileno(self) -> int:
        return self._display.fileno()

    def _read(self, window):
        wm_class = window.get_wm_class()
        if not wm_class or wm_class[1].lower() != "multiviewer":
            return None
        hints = window.get_full_property(Xatom.WM_NORMAL_HINTS, Xatom.WM_SIZE_HINTS)
        if hints is None or hints.format != 32 or len(hints.value) < 15:
            return None
        values = hints.value
        if not values[0] & Xutil.PAspect:
            return None
        # ICCCM aspect fields are signed 32-bit integers; Xlib returns the raw
        # property words as unsigned integers. Support both old and new hints.
        min_num, min_den, max_num, max_den = map(int, values[11:15])
        if not all(
            0 < value <= 0x7FFFFFFF for value in (min_num, min_den, max_num, max_den)
        ):
            return None
        if min_num * max_den != max_num * min_den:
            return None
        aspect = Fraction(min_num, min_den)
        if not math.isfinite(float(aspect)) or aspect <= 0:
            return None
        pid = window.get_full_property(self._pid, Xatom.CARDINAL)
        if pid is None or pid.format != 32 or len(pid.value) != 1 or pid.value[0] <= 0:
            return None
        name = window.get_full_property(self._name, self._utf8)
        title = None
        if name is not None and name.format == 8:
            try:
                title = bytes(name.value).decode("utf-8")
            except UnicodeDecodeError:
                pass
        if title is None:
            title = window.get_wm_name()
        if not isinstance(title, str) or not title:
            return None
        return (int(pid.value[0]), title), aspect

    def _update(self, ids):
        for wid in ids:
            window = self._windows.get(wid)
            if window is None:
                continue
            try:
                metadata = self._read(window)
            except error.BadWindow:
                self._windows.pop(wid, None)
                metadata = None
            if metadata is None:
                self._metadata.pop(wid, None)
            else:
                self._metadata[wid] = metadata

    def _publish(self) -> bool:
        aspects = {}
        ambiguous = set()
        for key, aspect in self._metadata.values():
            if key in aspects and aspects[key] != aspect:
                ambiguous.add(key)
            aspects[key] = aspect
        ratios = {
            key: float(aspect)
            for key, aspect in aspects.items()
            if key not in ambiguous
        }
        changed = ratios != self._ratios
        self._ratios = ratios
        return changed

    def _reconcile(self):
        clients = self._root.get_full_property(self._client_list, Xatom.WINDOW)
        ids = (
            set(map(int, clients.value))
            if clients is not None and clients.format == 32
            else set()
        )
        ids.discard(0)
        for wid in self._windows.keys() - ids:
            window = self._windows.pop(wid)
            self._metadata.pop(wid, None)
            window.change_attributes(
                event_mask=0, onerror=error.CatchError(error.BadWindow)
            )
        for wid in ids - self._windows.keys():
            window = self._display.create_resource_object("window", wid)
            # The following reads round-trip after this request. BadWindow is
            # expected if the client closes between listing and subscribing.
            window.change_attributes(
                event_mask=X.PropertyChangeMask | X.StructureNotifyMask,
                onerror=error.CatchError(error.BadWindow),
            )
            self._windows[wid] = window
        self._update(ids)
        self._display.flush()
        return self._publish()

    def drain(self) -> bool:
        """Consume queued events, including events queued by metadata reads."""
        previous = self._ratios
        while self._display.pending_events():
            reconcile = False
            dirty = set()
            while self._display.pending_events():
                event = self._display.next_event()
                wid = getattr(getattr(event, "window", None), "id", None)
                if event.type == X.DestroyNotify and wid in self._windows:
                    self._windows.pop(wid, None)
                    self._metadata.pop(wid, None)
                elif event.type == X.PropertyNotify:
                    if wid == self._root.id and event.atom == self._client_list:
                        reconcile = True
                    elif wid in self._windows and event.atom in self._properties:
                        dirty.add(wid)
            if reconcile:
                self._reconcile()
            else:
                self._update(dirty)
                self._publish()
        return self._ratios != previous

    def refresh(self) -> bool:
        """Reconcile clients and reread metadata; report changed public ratios."""
        previous = self._ratios
        self._reconcile()
        # Synchronous property replies may have already pulled events off the
        # socket; an fd reader alone would not see those buffered events.
        self.drain()
        return self._ratios != previous

    def ratios(self) -> dict[tuple[int, str], float]:
        """Return an independent snapshot, excluding conflicting identities."""
        return self._ratios.copy()

    def close(self):
        self._display.close()
