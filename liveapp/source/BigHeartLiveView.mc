import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

//! Standalone direct-sensor prototype: large red HR, large blue SpO2,
//! white time, updated from Sensor.enableSensorEvents().
class BigHeartLiveView extends WatchUi.View {

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

    private var _timer as Timer.Timer? = null;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _hrLarge = WatchUi.loadResource(Rez.Fonts.HrLarge) as Graphics.FontReference;
        _hrSmall = WatchUi.loadResource(Rez.Fonts.HrSmall) as Graphics.FontReference;
        _spo2 = WatchUi.loadResource(Rez.Fonts.Spo2) as Graphics.FontReference;
    }

    function onShow() as Void {
        var oldTimer = _timer;
        if (oldTimer != null) {
            oldTimer.stop();
            _timer = null;
        }

        if (Toybox has :Sensor) {
            try {
                Sensor.setEnabledSensors([
                    Sensor.SENSOR_ONBOARD_HEARTRATE,
                    Sensor.SENSOR_ONBOARD_PULSE_OXIMETRY
                ]);
                Sensor.enableSensorEvents(method(:onSensor));
            } catch (e) {
            }
        }

        _timer = new Timer.Timer();
        _timer.start(method(:onTick), 1000, true);
    }

    function onHide() as Void {
        var timer = _timer;
        if (timer != null) {
            timer.stop();
            _timer = null;
        }

        if (Toybox has :Sensor) {
            Sensor.enableSensorEvents(null);
            Sensor.setEnabledSensors([]);
        }
    }

    //! Direct live sensor callback, nominally 1 Hz.
    function onSensor(info as Sensor.Info) as Void {
        var hr = info.heartRate;
        if (hr != null && hr >= 20 && hr <= 300) {
            _hrText = hr.format("%d");
            _hrSource = "S";
        }

        var spo2 = info.oxygenSaturation;
        if (spo2 != null && spo2 >= 50 && spo2 <= 100) {
            _spo2Text = spo2.format("%d");
            _spo2Source = "S";
        }

        WatchUi.requestUpdate();
    }

    function onTick() as Void {
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var width = dc.getWidth();
        var height = dc.getHeight();
        var centerX = width / 2;

        // White time and source diagnostics (S = direct sensor), on separate
        // lines so neither is clipped by the round display edge.
        dc.setColor(COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, (height * 0.045).toNumber(), Graphics.FONT_XTINY,
                    formatTime(),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.drawText(centerX, (height * 0.105).toNumber(), Graphics.FONT_XTINY,
                    "HR:" + _hrSource + " O2:" + _spo2Source,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(COLOR_HR, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, (height * 0.390).toNumber(), hrFont(), _hrText,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        dc.setColor(COLOR_SPO2, Graphics.COLOR_TRANSPARENT);
        dc.drawText(centerX, (height * 0.785).toNumber(), _spo2 as Graphics.FontReference, _spo2Text,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function hrFont() as Graphics.FontReference {
        if (_hrText.length() <= 2 && _hrText.substring(0, 1) != "-") {
            return _hrLarge as Graphics.FontReference;
        }
        return _hrSmall as Graphics.FontReference;
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
}
