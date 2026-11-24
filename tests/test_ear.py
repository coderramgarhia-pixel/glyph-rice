"""Exercise the ear helper without connecting to Bluetooth hardware."""
import contextlib
import io
import json
import os
import tempfile
from pathlib import Path
import runpy
import struct
import unittest
from unittest.mock import MagicMock, patch


HELPER = Path(__file__).resolve().parents[1] / "config/quickshell/glyph/ear"


def frame(cmd, data):
    # Responses without the optional CRC flag.
    return struct.pack("<BHHHB", 0x55, 0x100, cmd, len(data), 0) + data


class EarTest(unittest.TestCase):
    def invoke(self, responses, args=()):
        rfcomm, sdp = MagicMock(), MagicMock()
        rfcomm.__enter__.return_value = rfcomm
        sdp.__enter__.return_value = sdp
        sdp.recv.return_value = b"\x19\x00\x03\x08\x01"
        rfcomm.recv.side_effect = responses
        output = io.StringIO()
        with tempfile.TemporaryDirectory() as run, patch.dict(os.environ, {"XDG_RUNTIME_DIR": run}), \
                patch("socket.socket", side_effect=[rfcomm, sdp]), \
                patch("sys.argv", [str(HELPER), "00:11:22:33:44:55", *args]), \
                contextlib.redirect_stdout(output):
            runpy.run_path(str(HELPER), run_name="__main__")
        self.sent = [c.args[0] for c in rfcomm.send.call_args_list]
        return json.loads(output.getvalue())

    def test_earbuds_fragmented_frames(self):
        data = frame(0x4007, bytes([3, 2, 100, 3, 95, 4, 80])) + frame(0x401E, bytes([1, 4, 0]))
        self.assertEqual(self.invoke([data[:5], data[5:11], data[11:]]),
                         {"l": 100, "r": 95, "case": 80, "mode": 4})

    def test_single_battery_without_anc(self):
        self.assertEqual(self.invoke([frame(0x4007, bytes([1, 6, 85])), TimeoutError()]), {"bat": 85})

    def test_battery_charging_bit(self):
        self.assertEqual(self.invoke([frame(0x4007, bytes([1, 2, 0x80 | 70])), TimeoutError()]), {"l": 70, "chg": ["l"]})

    def test_empty_anc_reply(self):
        self.assertEqual(self.invoke([frame(0x4007, bytes([1, 6, 50])) + frame(0x401E, b"")]), {"bat": 50})

    def test_no_battery_reply(self):
        with self.assertRaisesRegex(SystemExit, "no battery"):
            self.invoke([TimeoutError()])

    def test_invalid_battery_payload(self):
        for battery in (b"", bytes([2, 2, 100])):
            with self.subTest(battery=battery), self.assertRaisesRegex(SystemExit, "invalid battery"):
                self.invoke([frame(0x4007, battery), TimeoutError()])

    def test_device_disconnect(self):
        with self.assertRaisesRegex(SystemExit, "closed"):
            self.invoke([b""])

    # local change: buds app settings (all / set / fit)
    def test_all_settings(self):
        data = (frame(0x4007, bytes([2, 2, 90, 3, 80])) + frame(0x401E, bytes([1, 1, 0])) + frame(0x401F, bytes([3]))
                + frame(0x404E, bytes([1, 6])) + frame(0x404F, bytes([0])) + frame(0x400E, bytes([1, 1, 1]))
                + frame(0x4041, bytes([2])) + frame(0x4027, bytes([1])) + frame(0x4018, bytes([1, 2, 1, 2, 2]))
                + frame(0x4044, bytes(44)))
        self.assertEqual(self.invoke([data], ["all"]), {"l": 90, "r": 80, "mode": 1, "eq": 3, "bass": 3,
                                                        "spatial": 0, "inear": 1, "latency": 0, "dual": 1,
                                                        "gest": [[2, 1, 2, 2]], "ceq": [0, 0, 0]})

    def test_set_bass_off_keeps_valid_level(self):
        self.invoke([frame(0x4007, bytes([1, 6, 50])), TimeoutError()], ["set", "bass", "0"])
        first = self.sent[0]
        self.assertEqual(struct.unpack_from("<H", first, 3)[0], 0xF051)
        self.assertEqual(first[8:10], bytes([0, 2]))

    def test_fit_result(self):
        out = self.invoke([frame(0x4007, bytes([1, 6, 50])), frame(0xE00D, bytes([0, 1])), TimeoutError()], ["fit"])
        self.assertEqual(out["fit"], [0, 1])

    def test_gestures(self):
        out = self.invoke([frame(0x4007, bytes([1, 6, 50])) + frame(0x4018, bytes([3, 2, 1, 2, 2, 3, 1, 7, 10, 4, 1, 10, 23])),
                           TimeoutError()], ["all"])
        self.assertEqual(out["gest"], [[2, 1, 2, 2], [3, 1, 7, 10], [4, 1, 10, 23]])

    def test_gesture_truncated(self):
        out = self.invoke([frame(0x4007, bytes([1, 6, 50])) + frame(0x4018, bytes([2, 2, 1, 2, 2, 3, 1])), TimeoutError()], ["all"])
        self.assertEqual(out["gest"], [[2, 1, 2, 2]])

    def test_set_gesture_frame(self):
        self.invoke([frame(0x4007, bytes([1, 6, 50])), TimeoutError()], ["set", "gesture", "3.1.7.11"])
        first = self.sent[0]
        self.assertEqual(struct.unpack_from("<H", first, 3)[0], 0xF003)
        self.assertEqual(first[8:13], bytes([1, 3, 1, 7, 11]))

    def test_custom_eq_round_trip(self):
        self.invoke([frame(0x4007, bytes([1, 6, 50])), TimeoutError()], ["set", "ceq", "-4.2.6"])
        first = self.sent[0]
        self.assertEqual(struct.unpack_from("<H", first, 3)[0], 0xF041)
        p = first[8:-2]
        self.assertEqual(len(p), 53)
        # mid, treble, bass at 6/19/32; headroom = -max|gain|; frequencies untouched
        self.assertEqual([struct.unpack_from("<f", p, o)[0] for o in (1, 6, 19, 32, 10, 23, 36)], [-6, 2, 6, -4, 980, 3500, 140])
        # the buds answer 0x4044 with the same layout (44 bytes on CMF Buds Pro 2)
        out = self.invoke([frame(0x4007, bytes([1, 6, 50])) + frame(0x4044, p[:44]), TimeoutError()], ["all"])
        self.assertEqual(out["ceq"], [-4, 2, 6])

    def test_unknown_setting(self):
        with self.assertRaisesRegex(SystemExit, "unknown setting"):
            self.invoke([], ["set", "nope", "1"])


if __name__ == "__main__":
    unittest.main()
