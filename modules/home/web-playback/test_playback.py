import importlib.util
import io
import struct
import sys
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("web_playback", Path(__file__).with_name("playback.py"))
playback = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = playback
SPEC.loader.exec_module(playback)


class HandoffInputTests(unittest.TestCase):
    def test_shared_video_keeps_timestamp_but_cannot_expand_playlist(self):
        request = playback.validate_request({
            "url": "https://youtu.be/aqz-KE-bpKQ?list=PLunrelated&t=1m23s&si=tracking",
        })
        self.assertEqual(request.url, "https://www.youtube.com/watch?v=aqz-KE-bpKQ")
        self.assertEqual(request.start, 83)

    def test_current_player_position_overrides_old_share_timestamp(self):
        request = playback.validate_request({
            "url": "https://www.youtube.com/watch?v=aqz-KE-bpKQ&t=90",
            "start": 12.5,
        })
        self.assertEqual(request.start, 12.5)

    def test_untrusted_urls_cannot_escape_supported_services(self):
        for url in (
            "file:///etc/passwd",
            "https://www.youtube.com.evil.test/watch?v=aqz-KE-bpKQ",
            "https://www.youtube.com@evil.test/watch?v=aqz-KE-bpKQ",
            "https://www.youtube.com:1234/watch?v=aqz-KE-bpKQ",
            "https://www.youtube.com/watch?v=aqz-KE-bpKQ\n--script=/tmp/untrusted.lua",
            "https://www.youtube.com/playlist?list=PLunrelated",
            "https://www.youtube.com/watch?v=aqz-KE-bpKQ&v=jNQXAC9IVRw",
        ):
            with self.subTest(url=url), self.assertRaises(ValueError):
                playback.validate_request({"url": url})

    def test_native_requests_cannot_supply_player_options(self):
        with self.assertRaises(ValueError):
            playback.validate_request({
                "url": "https://youtu.be/aqz-KE-bpKQ", "script": "/tmp/untrusted.lua",
            })

    def test_nonfinite_or_boolean_start_times_are_rejected(self):
        for value in (float("nan"), float("inf"), -1, True):
            with self.subTest(value=value), self.assertRaises(ValueError):
                playback.validate_request({"url": "https://youtu.be/aqz-KE-bpKQ", "start": value})

    def test_twitch_live_does_not_inherit_a_position(self):
        request = playback.validate_request({"url": "https://www.twitch.tv/rifftrax?t=1h"})
        self.assertEqual(request.url, "https://www.twitch.tv/rifftrax")
        self.assertIsNone(request.start)
        with self.assertRaises(ValueError):
            playback.validate_request({"url": request.url, "start": 60})

    def test_native_framing_accepts_fragmented_pipe_reads(self):
        class FragmentedPipe(io.BytesIO):
            def read(self, size=-1):
                return super().read(min(size, 2))

        payload = b'{"url":"https://youtu.be/aqz-KE-bpKQ"}'
        stream = FragmentedPipe(struct.pack("=I", len(payload)) + payload)
        self.assertEqual(playback.read_frame(stream), {"url": "https://youtu.be/aqz-KE-bpKQ"})

    def test_native_framing_rejects_truncation_and_unbounded_lengths(self):
        for wire in (
            b"\x01\x00",
            struct.pack("=I", 10) + b"{}",
            struct.pack("=I", 0),
            struct.pack("=I", 65537),
        ):
            with self.subTest(wire=wire), self.assertRaises(ValueError):
                playback.read_frame(io.BytesIO(wire))


if __name__ == "__main__":
    unittest.main()
