const errorMonitoring = require('./errorMonitoring');

class MQTTHandler {
  
  /**
   * Handle incoming MQTT messages from Arduino
   * Topics: arduino/sensors, arduino/current, arduino/water/alert, power/source/selection
   */
  handleMQTTMessage(topic, message) {
    try {
      const payload = JSON.parse(message);
      
      switch (topic) {
        case 'arduino/sensors':
          this._processSensorTelemetry(payload);
          break;
        
        case 'arduino/current':
          this._processCurrentUpdate(payload);
          break;
        
        case 'arduino/water/alert':
          this._processWaterAlert(payload);
          break;
        
        case 'power/source/selection':
          this._processPowerSourceSelection(payload);
          break;
        
        default:
          console.log(\Received message on \:\, payload);
      }
    } catch (error) {
      console.error(\Error processing MQTT message on \: \\);
    }
  }
  
  // ============ MESSAGE HANDLERS ============
  
  /**
   * Process sensor telemetry from Arduino
   * Logs prediction error for model validation monitoring
   */
  _processSensorTelemetry(telemetry) {
    // Validate against model predictions if available
    if (telemetry.voltage_predicted && telemetry.voltage_actual) {
      errorMonitoring.logPredictionError(
        telemetry.voltage_predicted,
        telemetry.voltage_actual,
        telemetry.timestamp || new Date()
      );
    }
    
    console.log(\✓ Arduino Telemetry [PEM Model Validation]:\, {
      temperature: telemetry.temperature + '°C',
      voltage_actual: telemetry.voltage_actual + 'V',
      voltage_predicted: telemetry.voltage_predicted + 'V',
      current: telemetry.current + 'A',
      purity: telemetry.purity + '%',
      water_level: telemetry.water_level + 'L'
    });
  }
  
  /**
   * Process current setpoint update from MATLAB MPC
   */
  _processCurrentUpdate(payload) {
    console.log(\✓ Current Setpoint Updated: \A (from MATLAB MPC)\);
  }
  
  /**
   * Process water level alert from Arduino
   * Tank capacity: 10,000L, Alert when <1,000L, Safety reserve: >2,000L
   */
  _processWaterAlert(alert) {
    console.warn(\⚠️  Water Tank Alert: \ | Remaining: \L\);
  }
  
  /**
   * Process power source selection (grid vs solar)
   */
  _processPowerSourceSelection(payload) {
    console.log(\✓ Power Source Selection: \ (grid/solar/auto)\);
  }
}

module.exports = new MQTTHandler();
