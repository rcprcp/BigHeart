import Toybox.Graphics;
import Toybox.Lang;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.WatchUi;

//! Big Heart - heart rate and SpO2 in the largest normal-font numerals
//! that fit the Forerunner 265's round 416x416 AMOLED display.
//!
//! Heart rate is red, SpO2 is blue. The small time sits at the top.
//!
//! Values come from Garmin's sensor history. A watch face cannot turn the
//! optical sensors on by itself, so the numbers are the most recent samples
//! the watch already recorded (typically about once a minute).
class BigHeartView extends WatchUi.WatchFace {

    private const COLOR_BG = 0x000000;
    private const COLOR_HR = 0xFF4D4D;
    private const COLOR_SPO2 = 0x4FB6FF;
    private const COLOR_TIME = 0x9A9A9A;

    // Ambient / always-on colours. Drawn with thin strokes so the face
    // stays inside Garmin's AMOLED luminance and burn-in rules.
    private const COLOR_HR_AMBIENT = 0xA05050;
    private const COLOR_SPO2_AMBIENT = 0x3E7C9C;
    private const COLOR_TIME_AMBIENT = 0x606060;

    private const HR_LARGE_HEIGHT = 195;
    private const HR_SMALL_HEIGHT = 156;
    private const SPO2_HEIGHT = 104;

    private var _width as Number = 416;
    private var _height as Number = 416;
    private var _centerX as Number = 208;
    private var _centerY as Number = 208;
    private var _radius as Number = 204;

    private var _hrLarge as Graphics.FontReference? = null;
    private var _hrSmall as Graphics.FontReference? = null;
    private var _spo2 as Graphics.FontReference? = null;

    private var _hrText as String = "--";
    private var _spo2Text as String = "--";

    private var _sleeping as Boolean = false;
    private var _lastRefreshMin as Number = -1;
    private var _lastRefreshHour as Number = -1;

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _width = dc.getWidth();
        _height = dc.getHeight();
        _centerX = _width / 2;
        _centerY = _height / 2;

        var smallestSide = _width < _height ? _width : _height;
        _radius = smallestSide / 2 - 6;

        _hrLarge = WatchUi.loadResource(Rez.Fonts.HrLarge) as Graphics.FontReference;
        _hrSmall = WatchUi.loadResource(Rez.Fonts.HrSmall) as Graphics.FontReference;
        _spo2 = WatchUi.loadResource(Rez.Fonts.Spo2) as Graphics.FontReference;
    }

    function onShow() as Void {
    }

    function onHide() as Void {
    }

    function onEnterSleep() as Void {
        _sleeping = true;
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _sleeping = false;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var clock = System.getClockTime();
        var lowPower = isLowPower();

        if (clock.min != _lastRefreshMin || clock.hour != _lastRefreshHour) {
            refreshHeartRate();
            refreshOxygenSaturation();
            _lastRefreshMin = clock.min;
            _lastRefreshHour = clock.hour;
        }

        dc.setColor(COLOR_BG, COLOR_BG);
        dc.clear();

        if (lowPower) {
            drawAmbient(dc, clock);
        } else {
            drawFullPower(dc, clock);
        }
    }

    //! True when the AMOLED display is in its always-on (dimmed) state.
    private function isLowPower() as Boolean {
        if (Toybox has :System && System has :getDisplayMode) {
            var mode = System.getDisplayMode();
            if (mode == System.DISPLAY_MODE_HIGH_POWER) {
                return false;
            }
            if (mode == System.DISPLAY_MODE_LOW_POWER || mode == System.DISPLAY_MODE_OFF) {
                return true;
            }
        }
        return _sleeping;
    }

    private function drawFullPower(dc as Graphics.Dc, clock as System.ClockTime) as Void {
        // Small time at the top, where there is room inside the circle.
        dc.setColor(COLOR_TIME, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, scaledY(0.053), Graphics.FONT_XTINY, formatTime(clock),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(COLOR_HR, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, scaledY(0.373), hrFontFor(_hrText), _hrText,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(COLOR_SPO2, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX, scaledY(0.788), _spo2 as Graphics.FontReference, _spo2Text,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    //! Ambient mode uses thin strokes instead of the filled font. The filled
    //! font at this size would exceed the luminance budget that protects an
    //! AMOLED panel in always-on mode. A small offset is applied each minute
    //! so no pixel stays on long enough to burn in.
    private function drawAmbient(dc as Graphics.Dc, clock as System.ClockTime) as Void {
        var shift = ambientShift(clock.min);

        dc.setColor(COLOR_TIME_AMBIENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX + shift[0], scaledY(0.053) + shift[1], Graphics.FONT_XTINY,
                    formatTime(clock),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var ambientHrHeight = _hrText.length() <= 2 ? HR_LARGE_HEIGHT : HR_SMALL_HEIGHT;
        SegmentFont.draw(dc, _hrText, _centerX, scaledY(0.373), scaledHeight(ambientHrHeight),
                         _width - 24, _centerX, _centerY, _radius,
                         COLOR_HR_AMBIENT, true, shift[0], shift[1]);

        SegmentFont.draw(dc, _spo2Text, _centerX, scaledY(0.788), scaledHeight(SPO2_HEIGHT),
                         _width - 24, _centerX, _centerY, _radius,
                         COLOR_SPO2_AMBIENT, true, shift[0], shift[1]);
    }

    //! Use the largest font that still fits inside the circle for the number
    //! of digits being shown.
    private function hrFontFor(text as String) as Graphics.FontReference {
        if (text.length() <= 2 && text.substring(0, 1) != "-") {
            return _hrLarge as Graphics.FontReference;
        }
        return _hrSmall as Graphics.FontReference;
    }

    private function scaledY(fraction as Float) as Number {
        return (_height * fraction).toNumber();
    }

    private function scaledHeight(pixels as Number) as Number {
        return (pixels * _height / 416.0).toNumber();
    }

    private function formatTime(clock as System.ClockTime) as String {
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

    //! Offsets large enough that the same pixels are not left on for minutes.
    private function ambientShift(minute as Number) as [Number, Number] {
        switch (minute % 4) {
            case 0:  return [0, 0];
            case 1:  return [6, 2];
            case 2:  return [-6, 0];
            default: return [0, 6];
        }
    }

    private function refreshHeartRate() as Void {
        _hrText = "--";

        var iterator = SensorHistory.getHeartRateHistory({
            :period => 24 * 60 * 60,
            :order => SensorHistory.ORDER_NEWEST_FIRST
        });

        var sample = iterator.next();
        if (sample == null) {
            return;
        }

        var raw = sample.data;
        if (raw == null) {
            return;
        }

        var value = sampleValue(raw);
        if (value < 20 || value > 300) {
            return;
        }

        _hrText = value.format("%d");
    }

    private function refreshOxygenSaturation() as Void {
        _spo2Text = "--";

        var iterator = SensorHistory.getOxygenSaturationHistory({
            :period => 24 * 60 * 60,
            :order => SensorHistory.ORDER_NEWEST_FIRST
        });

        var sample = iterator.next();
        if (sample == null) {
            return;
        }

        var raw = sample.data;
        if (raw == null) {
            return;
        }

        var value = sampleValue(raw);
        if (value < 50 || value > 100) {
            return;
        }

        _spo2Text = value.format("%d");
    }

    private function sampleValue(data as Number or Float) as Number {
        if (data instanceof Lang.Float) {
            return ((data as Lang.Float) + 0.5).toNumber();
        }
        return data as Lang.Number;
    }
}
