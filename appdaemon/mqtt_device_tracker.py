import appdaemon.plugins.hass.hassapi as hass


class mqtt_device_tracker(hass.Hass):
    def initialize(self):
        self.listen_state(self.inputhandler, self.args["trigger"])

    def inputhandler(self, entity, attribute, old, new, kwargs):
        confidence = float(self.get_state(self.args["trigger"]))
        state = self.get_state(self.args["device"])
        device_topic = self.args["device_topic"]

        device = self.args["device"]
 
        # self.log(device)
        # self.log(confidence)
        # self.log(state)

        if state == "not_home" and confidence > 10:
            # self.log(device_topic)
            # self.log("home")
            self.call_service("mqtt/publish", topic=device_topic, payload="home")
        elif state == "home" and confidence <= 10:
            # self.log(device_topic)
            # self.log("not_home")
            self.call_service("mqtt/publish", topic=device_topic, payload="not_home")
