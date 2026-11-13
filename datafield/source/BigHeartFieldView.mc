import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

//! Prototype full-screen data field: large red HR, large blue SpO2, white time.
//! Intended to be placed alone on a one-field activity data screen.
class BigHeartFieldView extends WatchUi.DataField {

    private const COLOR_HR = 0xFF4D4D;
    private const COLOR_SPO2 = 0x4FB6FF;
    private const COLOR_WHITE = 0xFFFFFF;

    private var _hrLarge as Graphics.FontReference? = null;
    private var _hrSmall as Graphics.FontReference? = null;
    private var _spo2 as Graphics.FontReference? = null;

    private var _hrText as String = "--";
    private var _spo2Text as String = "--";
    private var _hrSource as String = "-";
    private var _spo2Source as String = "-";

    private var _historyHr as Number = -1;
    private var _historySpo2 as Number = -1;
    private var _lastHistoryCheck as Number = -60000;

    function initialize() {
        DataField.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _hrLarge = WatchUi.loadResource(Rez.Fonts.HrLarge) as Graphics.FontReference;
        _hrSmall = WatchUi.loadResource(Rez.Fonts.HrSmall) as Graphics.FontReference;
        _spo2 = WatchUi.loadResource(Rez.Fonts.Spo2) as Graphics.FontReference;
    }

    //! Called by the activity once per second.
    function compute(info as Activity.Info) as Void {
        var hr = info.currentHeartRate;
        var hrValid = false;
        if (hr != null && hr >= 20 && hr <= 300) {
            _hrText = hr.format("%d");
            _hrSource = "C";
            hrValid = true;
        }

        var spo2 = info.currentOxygenSaturation;
        var spo2Valid = false;
        if (spo2 != null && spo2 >= 50 && spo2 <= 100) {
            _spo2Text = spo2.format("%d");
            _spo2Source = "C";
            spo2Valid = true;
        }

        if (!hrValid || !spo2Valid) {
            var now = System.getTimer();
            if (now - _lastHistoryCheck >= 60000) {
                _lastHistoryCheck = now;
                _historyHr = readHeartRateHistory();
                _historySpo2 = readSpo2History();
            }

            if (!hrValid) {
                if (_historyHr >= 0) {
                    _hrText = _historyHr.format("%d");
                    _hrSource = "H";
                } else {
                    _hrText = "--";
                    _hrSource = "-";
                }
            }

            if (!spo2Valid) {
                if (_historySpo2 >= 0) {
                    _spo2Text = _historySpo2.format("%d");
                    _spo2Source = "H";
                } else {
                    _spo2Text = "--";
                    _spo2Source = "-";
                }
            }
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2;

        // White time plus source diagnostics: C = current activity value,
        // H = sensor history, - = unavailable.
        dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, scaledY(height, 0.045), Graphics.FONT_XTINY,
                    formatTime() + "  HR:" + _hrSource + " O2:" + _spo2Source,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(COLOR_HR, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, scaledY(height, 0.36), hrFont(), _hrText,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(COLOR_SPO2, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, scaledY(height, 0.80), _spo2 as Graphics.FontReference, _spo2Text,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function hrFont() as Graphics.FontReference {
        if (_hrText.length() <= 2 && _hrText.substring(0, 1) != "-") {
            return _hrLarge as Graphics.FontReference;
        }
        return _hrSmall as Graphics.FontReference;
    }

    private function scaledY(height as Number, fraction as Float) as Number {
        return (height * fraction).toNumber();
    }

    private function formatTime() as String {
        var clock = System.getClockTime();
        var settings = System.getDeviceSettings();
        if (settings.is24Hour) {
            return Lang.format("$1$:$2$", [clock.hour.format("%02d"), clock.min.format("%02d")]);
        }

        var hour = clock.hour % 12;
        if (hour == 0) {
            hour = 12;
        }
        var suffix = clock.hour < 12 ? "AM" : "PM";
        return Lang.format("$1$:$2$ $3$", [hour, clock.min.format("%02d"), suffix]);
    }

    private function readHeartRateHistory() as Number {
        if (!(Toybox has :SensorHistory) || !(SensorHistory has :getHeartRateHistory)) {
            return -1;
        }

        var iterator = SensorHistory.getHeartRateHistory({
            :period => 10,
            :order => SensorHistory.ORDER_NEWEST_FIRST
        });
        var bestValue = -1;
        var bestWhen = -1;
        for (var i = 0; i < 10; i++) {
            var sample = iterator.next();
            if (sample == null) {
                break;
            }
            var raw = sample.data;
            if (raw == null) {
                continue;
            }
            var value = sampleValue(raw);
            if (value < 20 || value > 300) {
                continue;
            }
            var when = sample.when.value();
            if (when > bestWhen) {
                bestWhen = when;
                bestValue = value;
            }
        }
        return bestValue;
    }

    private function readSpo2History() as Number {
        if (!(Toybox has :SensorHistory) || !(SensorHistory has :getOxygenSaturationHistory)) {
            return -1;
        }

        var iterator = SensorHistory.getOxygenSaturationHistory({
            :order => SensorHistory.ORDER_NEWEST_FIRST
        });
        var lastValue = -1;
        for (var i = 0; i < 200; i++) {
            var sample = iterator.next();
            if (sample == null) {
                break;
            }
            var raw = sample.data;
            if (raw == null) {
                continue;
            }
            var value = sampleValue(raw);
            if (value < 50 || value > 100) {
                continue;
            }
            lastValue = value;
        }
        return lastValue;
    }

    private function sampleValue(data as Number or Float) as Number {
        if (data instanceof Lang.Float) {
            return ((data as Lang.Float) + 0.5).toNumber();
        }
        return data as Lang.Number;
    }
}
