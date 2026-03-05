const fs = require('fs');
const path = require('path');
const { formatISO, subDays, parseISO } = require('date-fns');

const ERROR_LOG_FILE = './data/error_log.json';
const ERROR_THRESHOLD = 15; // 15% MAPE threshold for retraining flag

class ErrorMonitoring {
  
  constructor() {
    this.errors = this.loadErrorLog();
    this.retrainingNeeded = false;
  }
  
  /**
   * Log prediction error from MQTT telemetry or manual test
   * Called when Arduino publishes actual vs predicted values
   */
  logPredictionError(predicted, actual, timestamp = new Date()) {
    const error = {
      id: require('uuid').v4(),
      timestamp: formatISO(new Date(timestamp)),
      predicted: parseFloat(predicted),
      actual: parseFloat(actual),
      absoluteError: Math.abs(predicted - actual),
      relativeError: Math.abs((predicted - actual) / actual),
      percentError: Math.abs((predicted - actual) / actual) * 100
    };
    
    this.errors.push(error);
    this.saveErrorLog();
    this._checkRetrainingThreshold();
    
    return error;
  }
  
  /**
   * Get 7-day rolling average error metrics
   * Used to determine if retraining is needed (threshold: 15% MAPE)
   */
  getRollingAverageError(days = 7) {
    const cutoffDate = subDays(new Date(), days);
    const recentErrors = this.errors.filter(e => {
      const errorDate = parseISO(e.timestamp);
      return errorDate >= cutoffDate;
    });
    
    if (recentErrors.length === 0) {
      return null;
    }
    
    // Calculate RMSE
    const rmse = Math.sqrt(
      recentErrors.reduce((sum, e) => sum + e.absoluteError ** 2, 0) / recentErrors.length
    );
    
    // Calculate MAE
    const mae = recentErrors.reduce((sum, e) => sum + e.absoluteError, 0) / recentErrors.length;
    
    // Calculate MAPE (Mean Absolute Percentage Error)
    const mape = recentErrors.reduce((sum, e) => sum + e.percentError, 0) / recentErrors.length;
    
    return {
      days,
      sampleCount: recentErrors.length,
      RMSE: rmse.toFixed(4),
      MAE: mae.toFixed(4),
      MAPE: mape.toFixed(2),
      exceedsThreshold: mape > ERROR_THRESHOLD
    };
  }
  
  /**
   * Get current error status (7-day, 30-day, all-time rolling averages)
   */
  getErrorStatus() {
    const rolling7 = this.getRollingAverageError(7);
    const rolling30 = this.getRollingAverageError(30);
    const allTime = this.getRollingAverageError(9999);
    
    return {
      rolling7Day: rolling7,
      rolling30Day: rolling30,
      allTime: allTime,
      retrainingFlag: this.retrainingNeeded,
      threshold: ERROR_THRESHOLD + '%'
    };
  }
  
  /**
   * Get retraining flag status
   * Flag set when 7-day MAPE exceeds 15% threshold
   */
  getRetrainingFlag() {
    const rolling = this.getRollingAverageError(7);
    
    return {
      retrainingNeeded: this.retrainingNeeded,
      threshold: ERROR_THRESHOLD + '%',
      currentError: rolling?.MAPE + '%' || 'N/A',
      recommendation: this.retrainingNeeded 
        ? '🔔 Run MATLAB retraining with new data to improve PEM model accuracy'
        : '✓ Model performance within acceptable range',
      samplesUsed: rolling?.sampleCount || 0
    };
  }
  
  /**
   * Start continuous monitoring background process
   */
  startMonitoring() {
    setInterval(() => {
      this._checkRetrainingThreshold();
    }, 60000); // Check every minute
    
    console.log('✓ Error monitoring started (60s check interval)');
  }
  
  // ============ PRIVATE METHODS ============
  
  _checkRetrainingThreshold() {
    const rolling = this.getRollingAverageError(7);
    
    if (rolling && rolling.exceedsThreshold) {
      this.retrainingNeeded = true;
      console.warn(\⚠️  RETRAINING NEEDED: 7-day MAPE \% exceeds threshold \%\);
    } else {
      this.retrainingNeeded = false;
    }
  }
  
  loadErrorLog() {
    if (!fs.existsSync(ERROR_LOG_FILE)) {
      return [];
    }
    return JSON.parse(fs.readFileSync(ERROR_LOG_FILE, 'utf8'));
  }
  
  saveErrorLog() {
    fs.writeFileSync(ERROR_LOG_FILE, JSON.stringify(this.errors, null, 2));
  }
}

module.exports = new ErrorMonitoring();
