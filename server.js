const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');
const path = require('path');
const mqtt = require('mqtt');
const fs = require('fs');

// Import custom modules
const modelVersioning = require('./src/services/modelVersioning');
const errorMonitoring = require('./src/services/errorMonitoring');
const dataLifecycle = require('./src/services/dataLifecycle');
const exportService = require('./src/services/exportService');
const mqttHandler = require('./src/services/mqttHandler');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(bodyParser.json({ limit: '50mb' }));
app.use(bodyParser.urlencoded({ limit: '50mb', extended: true }));
app.use(express.static('public'));

// Initialize directories
const requiredDirs = ['./data', './data/archive', './exports'];
requiredDirs.forEach(dir => {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
});

// Global MQTT client
let mqttClient;

// ============ ROUTES ============

// 1. GET current active model
app.get('/api/models/active', (req, res) => {
  try {
    const activeModel = modelVersioning.getActiveModel();
    res.json(activeModel);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// 2. GET all model versions (archive + active)
app.get('/api/models/history', (req, res) => {
  try {
    const history = modelVersioning.getModelHistory();
    res.json(history);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// 3. GET specific archived model
app.get('/api/models/archive/:version', (req, res) => {
  try {
    const model = modelVersioning.getArchivedModel(req.params.version);
    res.json(model);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// 4. COMPARE two models
app.post('/api/models/compare', (req, res) => {
  try {
    const { version1, version2 } = req.body;
    const comparison = modelVersioning.compareModels(version1, version2);
    res.json(comparison);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// 5. UPLOAD new model (validation + comparison)
app.post('/api/models/upload', (req, res) => {
  try {
    const { modelData, uploadReason } = req.body;
    const validation = modelVersioning.validateAndCompareModel(modelData, uploadReason);
    res.json(validation);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// 6. APPROVE model replacement
app.post('/api/models/approve', (req, res) => {
  try {
    const { newModelData, uploadReason } = req.body;
    const result = modelVersioning.promoteModelToActive(newModelData, uploadReason);
    res.json(result);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// 7. GET error monitoring status
app.get('/api/monitoring/errors', (req, res) => {
  try {
    const status = errorMonitoring.getErrorStatus();
    res.json(status);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// 8. GET retraining flag
app.get('/api/monitoring/retraining-flag', (req, res) => {
  try {
    const flag = errorMonitoring.getRetrainingFlag();
    res.json(flag);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// 9. RECORD prediction error (from MQTT or manual test)
app.post('/api/monitoring/log-error', (req, res) => {
  try {
    const { predicted, actual, timestamp } = req.body;
    errorMonitoring.logPredictionError(predicted, actual, timestamp);
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// 10. EXPORT lifecycle history
app.get('/api/export/lifecycle', async (req, res) => {
  try {
    const format = req.query.format || 'json'; // json, csv, zip
    const filePath = await exportService.exportLifecycleHistory(format);
    res.download(filePath, (err) => {
      if (!err) fs.unlinkSync(filePath); // Clean up
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// 11. UPLOAD CSV/JSON file for model training
app.post('/api/data/upload-file', (req, res) => {
  try {
    const { fileData, fileName } = req.body;
    const result = dataLifecycle.processUserUploadedFile(fileData, fileName);
    res.json(result);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// 12. GET data sources priority order
app.get('/api/data/sources', (req, res) => {
  try {
    const sources = dataLifecycle.getDataSourceStatus();
    res.json(sources);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// ============ MQTT INTEGRATION ============

function initializeMQTT() {
  const brokerUrl = process.env.MQTT_URL || 'mqtt://localhost:1883';
  
  mqttClient = mqtt.connect(brokerUrl);
  
  mqttClient.on('connect', () => {
    console.log('✓ Connected to MQTT broker');
    mqttClient.subscribe('arduino/sensors', (err) => {
      if (err) console.error('MQTT subscribe error:', err);
    });
  });
  
  mqttClient.on('message', (topic, message) => {
    mqttHandler.handleMQTTMessage(topic, message.toString());
  });
  
  mqttClient.on('error', (error) => {
    console.error('MQTT error:', error);
  });
}

// ============ SERVER STARTUP ============

app.listen(PORT, () => {
  console.log(\
╔════════════════════════════════════════════════════╗
║  PEM ELECTROLYZER DASHBOARD - RUNNING              ║
║  http://localhost:\                          ║
║  Data Lifecycle Management System Active            ║
╚════════════════════════════════════════════════════╝
  \);
  
  // Initialize systems
  initializeMQTT();
  errorMonitoring.startMonitoring();
  dataLifecycle.initializeDefaultData();
});

module.exports = { app, mqttClient };
