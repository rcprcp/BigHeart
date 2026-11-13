import Toybox.Complications;
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

    // Ambient / always-on colours. Smaller numerals and dim colours keep the
    // face inside Garmin's AMOLED luminance and burn-in rules.
    private const COLOR_HR_AMBIENT = 0xA05050;
    private const COLOR_SPO2_AMBIENT = 0x3E7C9C;
    private const COLOR_TIME_AMBIENT = 0x606060;

    private var _width as Number = 416;
    private var _height as Number = 416;
    private var _centerX as Number = 208;
    private var _hrLarge as Graphics.FontReference? = null;
    private var _hrSmall as Graphics.FontReference? = null;
    private var _spo2 as Graphics.FontReference? = null;
    private var _hrAmbient as Graphics.FontReference? = null;
    private var _spo2Ambient as Graphics.FontReference? = null;

    private var _hrText as String = "--";
    private var _spo2Text as String = "--";

    private var _sleeping as Boolean = false;

    // The system Pulse Ox complication carries the current reading, the same
    // value shown by the Pulse Ox glance. SensorHistory can lag behind it.
    private var _pulseOxId as Complications.Id =
        new Complications.Id(Complications.COMPLICATION_TYPE_PULSE_OX);

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _width = dc.getWidth();
        _height = dc.getHeight();
        _centerX = _width / 2;

        _hrLarge = WatchUi.loadResource(Rez.Fonts.HrLarge) as Graphics.FontReference;
        _hrSmall = WatchUi.loadResource(Rez.Fonts.HrSmall) as Graphics.FontReference;
        _spo2 = WatchUi.loadResource(Rez.Fonts.Spo2) as Graphics.FontReference;
        _hrAmbient = WatchUi.loadResource(Rez.Fonts.HrAmbient) as Graphics.FontReference;
        _spo2Ambient = WatchUi.loadResource(Rez.Fonts.Spo2Ambient) as Graphics.FontReference;

        Complications.subscribeToUpdates(_pulseOxId);
        Complications.registerComplicationChangeCallback(method(:onComplicationChange));
    }

    //! Ask for a redraw when the Pulse Ox complication changes.
    function onComplicationChange(id as Complications.Id) as Void {
        if (id.equals(_pulseOxId)) {
            WatchUi.requestUpdate();
        }
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

        // Refresh on every update. Watch faces are redrawn on wrist raise and
        // at least once a minute, and the values can appear as soon as the
        // watch records its first sensor-history sample.
        refreshHeartRate();
        refreshOxygenSaturation();

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

    //! Ambient mode keeps the same normal font and layout, but uses smaller
    //! numerals and dim colours so the face stays within the AMOLED luminance
    //! budget. Offsetting the readout each minute also avoids leaving the same
    //! pixels lit for long periods.
    private function drawAmbient(dc as Graphics.Dc, clock as System.ClockTime) as Void {
        var shift = ambientShift(clock.min);

        dc.setColor(COLOR_TIME_AMBIENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX + shift[0], scaledY(0.053) + shift[1], Graphics.FONT_XTINY,
                    formatTime(clock),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(COLOR_HR_AMBIENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX + shift[0], scaledY(0.373) + shift[1],
                    _hrAmbient as Graphics.FontReference, _hrText,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(COLOR_SPO2_AMBIENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_centerX + shift[0], scaledY(0.788) + shift[1],
                    _spo2Ambient as Graphics.FontReference, _spo2Text,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
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

        var iterator = heartRateIterator();
        if (iterator == null) {
            return;
        }

        var value = latestValue(iterator, 20, 300, 10);
        if (value >= 0) {
            _hrText = value.format("%d");
        }
    }

    private function refreshOxygenSaturation() as Void {
        _spo2Text = "--";

        var iterator = oxygenSaturationIterator();
        if (iterator == null) {
            return;
        }

        // SpO2 history has known quirks on real watches: the requested order
        // is ignored (samples come oldest-first), timestamps can be out of
        // order, and the newest entry can be empty. Read the whole available
        // history and keep the last valid sample, which is the newest data on
        // these devices.
        var value = lastValidValue(iterator, 50, 100, 1000);
        if (value >= 0) {
            _spo2Text = value.format("%d");
        }
    }

    private function heartRateIterator() as SensorHistoryIterator? {
        if ((Toybox has :SensorHistory) && (SensorHistory has :getHeartRateHistory)) {
            // A Number period means "last N samples", not seconds.
            return SensorHistory.getHeartRateHistory({
                :period => 10,
                :order => SensorHistory.ORDER_NEWEST_FIRST
            });
        }
        return null;
    }

    private function oxygenSaturationIterator() as SensorHistoryIterator? {
        if ((Toybox has :SensorHistory) && (SensorHistory has :getOxygenSaturationHistory)) {
            // No period: ask for the entire available history so the newest
            // sample is included even when ORDER_NEWEST_FIRST is ignored.
            return SensorHistory.getOxygenSaturationHistory({
                :order => SensorHistory.ORDER_NEWEST_FIRST
            });
        }
        return null;
    }

    private function lastValidValue(iterator as SensorHistoryIterator, minimum as Number,
                                    maximum as Number, maxSamples as Number) as Number {
        var lastValue = -1;

        for (var i = 0; i < maxSamples; i++) {
            var sample = iterator.next();
            if (sample == null) {
                break;
            }

            var raw = sample.data;
            if (raw == null) {
                continue;
            }

            var value = sampleValue(raw);
            if (value < minimum || value > maximum) {
                continue;
            }

            lastValue = value;
        }

        return lastValue;
    }

    private function latestValue(iterator as SensorHistoryIterator, minimum as Number,
                                 maximum as Number, maxSamples as Number) as Number {
        var bestValue = -1;
        var bestWhen = -1;

        for (var i = 0; i < maxSamples; i++) {
            var sample = iterator.next();
            if (sample == null) {
                break;
            }

            var raw = sample.data;
            if (raw == null) {
                continue;
            }

            var value = sampleValue(raw);
            if (value < minimum || value > maximum) {
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

    private function sampleValue(data as Number or Float) as Number {
        if (data instanceof Lang.Float) {
            return ((data as Lang.Float) + 0.5).toNumber();
        }
        return data as Lang.Number;
    }
}
