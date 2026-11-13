import Toybox.Application.Storage;
import Toybox.Background;
import Toybox.Lang;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Time;

//! Runs periodically while Big Heart is the active watch face. Watch faces
//! cannot read the live optical sensors directly, but a background service
//! can. Store the current SpO2 for the face to display.
(:background)
class BigHeartServiceDelegate extends System.ServiceDelegate {

    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        var value = -1;

        if (Toybox has :Sensor) {
            var info = Sensor.getInfo();
            if (info != null) {
                var spo2 = info.oxygenSaturation;
                if (spo2 != null && spo2 >= 50 && spo2 <= 100) {
                    value = spo2;
                }
            }
        }

        var runs = Storage.getValue("BigHeartSvcRuns");
        var runCount = 0;
        if (runs instanceof Lang.Number) {
            runCount = runs as Lang.Number;
        }
        runCount += 1;
        Storage.setValue("BigHeartSvcRuns", runCount);
        Storage.setValue("BigHeartSvcValue", value);
        Storage.setValue("BigHeartSvcTime", Time.now().value());

        if (value >= 0) {
            Storage.setValue("BigHeartSpo2", value);
            Storage.setValue("BigHeartSpo2Time", Time.now().value());
        }

        Background.exit(value);
    }
}
