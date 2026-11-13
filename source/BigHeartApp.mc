import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

(:background)
class BigHeartApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
    }

    function onStop(state as Dictionary?) as Void {
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        if (Toybox has :Background) {
            Background.registerForTemporalEvent(new Time.Duration(5 * 60));
        }
        return [ new BigHeartView() ];
    }

    function getServiceDelegate() as [ServiceDelegate] {
        return [ new BigHeartServiceDelegate() ];
    }

    function onBackgroundData(data as PersistableType) as Void {
        WatchUi.requestUpdate();
    }
}
