const fs = require('fs');
const path = require('path');
const archiver = require('archiver');
const { stringify } = require('csv-stringify/sync');
const { formatISO } = require('date-fns');

const EXPORT_DIR = './exports';
const DATA_DIR = './data';

class ExportService {
  
  /**
   * Export complete lifecycle history (CSV, JSON, or ZIP)
   * For thesis: includes ALL model versions, comparison metrics, error trends
   */
  async exportLifecycleHistory(format = 'json') {
    const timestamp = formatISO(new Date()).slice(0, 19).replace(/:/g, '-');
    
    switch (format.toLowerCase()) {
      case 'csv':
        return this._exportAsCSV(timestamp);
      case 'zip':
        return await this._exportAsZIP(timestamp);
      case 'json':
      default:
        return this._exportAsJSON(timestamp);
    }
  }
  
  // ============ EXPORT IMPLEMENTATIONS ============
  
  _exportAsJSON(timestamp) {
    const lifecycle = this._compileCompleteLifecycle();
    const fileName = \lifecycle_\.json\;
    const filePath = path.join(EXPORT_DIR, fileName);
    
    if (!fs.existsSync(EXPORT_DIR)) {
      fs.mkdirSync(EXPORT_DIR, { recursive: true });
    }
    
    fs.writeFileSync(filePath, JSON.stringify(lifecycle, null, 2));
    console.log(\✓ Exported lifecycle as JSON: \\);
    
    return filePath;
  }
  
  _exportAsCSV(timestamp) {
    const registry = this._getModelRegistry();
    const errors = this._getErrorLog();
    
    if (!fs.existsSync(EXPORT_DIR)) {
      fs.mkdirSync(EXPORT_DIR, { recursive: true });
    }
    
    // Export model registry as CSV
    const registryCSV = stringify(registry, {
      header: true,
      columns: {
        version: 'Version',
        status: 'Status',
        date: 'Date',
        error: 'Error (%)',
        RMSE: 'RMSE',
        MAE: 'MAE',
        MAPE: 'MAPE (%)',
        R2: 'R²',
        replacementReason: 'Replacement Reason',
        trainingDataRange: 'Training Range',
        samples: 'Samples',
        purityCheck: 'O₂ Purity (%)'
      }
    });
    
    const registryPath = path.join(EXPORT_DIR, \model_registry_\.csv\);
    fs.writeFileSync(registryPath, registryCSV);
    
    // Export error log as CSV
    const errorCSV = stringify(errors.slice(-1000), {
      header: true,
      columns: {
        timestamp: 'Timestamp',
        predicted: 'Predicted',
        actual: 'Actual',
        percentError: 'Error (%)'
      }
    });
    
    const errorPath = path.join(EXPORT_DIR, \rror_log_\.csv\);
    fs.writeFileSync(errorPath, errorCSV);
    
    console.log(\✓ Exported lifecycle as CSV: model_registry_\.csv\);
    
    return registryPath;
  }
  
  async _exportAsZIP(timestamp) {
    if (!fs.existsSync(EXPORT_DIR)) {
      fs.mkdirSync(EXPORT_DIR, { recursive: true });
    }
    
    const zipFileName = \lifecycle_\.zip\;
    const zipPath = path.join(EXPORT_DIR, zipFileName);
    
    return new Promise((resolve, reject) => {
      const output = fs.createWriteStream(zipPath);
      const archive = archiver('zip', { zlib: { level: 9 } });
      
      archive.on('error', reject);
      output.on('close', () => {
        console.log(\✓ Exported lifecycle as ZIP: \\);
        resolve(zipPath);
      });
      
      archive.pipe(output);
      
      // Add model registry
      const registry = this._getModelRegistry();
      archive.append(JSON.stringify(registry, null, 2), { name: 'model_registry.json' });
      
      // Add error log
      const errors = this._getErrorLog();
      archive.append(JSON.stringify(errors, null, 2), { name: 'error_log.json' });
      
      // Add all archived models
      if (fs.existsSync(path.join(DATA_DIR, 'archive'))) {
        archive.directory(path.join(DATA_DIR, 'archive') + '/', 'models/archive');
      }
      
      // Add active model
      if (fs.existsSync(path.join(DATA_DIR, 'initial_model.json'))) {
        archive.file(path.join(DATA_DIR, 'initial_model.json'), { name: 'models/active_model.json' });
      }
      
      archive.finalize();
    });
  }
  
  _compileCompleteLifecycle() {
    const registry = this._getModelRegistry();
    const errors = this._getErrorLog();
    const activeModel = this._getActiveModel();
    
    return {
      exportDate: formatISO(new Date()),
      exportType: 'Complete Lifecycle History - All Model Versions',
      summary: {
        totalVersions: registry.length,
        activeVersion: registry.find(m => m.status === 'active')?.version || 'N/A',
        totalErrorRecords: errors.length,
        archivedModels: registry.filter(m => m.status === 'archived').length
      },
      models: {
        registry,
        activeModel,
        history: registry.map(m => ({
          version: m.version,
          status: m.status,
          date: m.date,
          metrics: {
            error: m.error,
            RMSE: m.RMSE,
            MAE: m.MAE,
            MAPE: m.MAPE,
            R2: m.R2,
            purityCheck: m.purityCheck
          },
          replacementReason: m.replacementReason,
          trainingDataRange: m.trainingDataRange,
          samples: m.samples,
          pemParameters: m.pemParameters
        }))
      },
      errorAnalysis: {
        totalErrors: errors.length,
        recentErrors: errors.slice(-100)
      }
    };
  }
  
  _getModelRegistry() {
    const registryPath = path.join(DATA_DIR, 'model_registry.json');
    if (!fs.existsSync(registryPath)) return [];
    return JSON.parse(fs.readFileSync(registryPath, 'utf8'));
  }
  
  _getErrorLog() {
    const logPath = path.join(DATA_DIR, 'error_log.json');
    if (!fs.existsSync(logPath)) return [];
    return JSON.parse(fs.readFileSync(logPath, 'utf8'));
  }
  
  _getActiveModel() {
    const modelPath = path.join(DATA_DIR, 'initial_model.json');
    if (!fs.existsSync(modelPath)) return null;
    return JSON.parse(fs.readFileSync(modelPath, 'utf8'));
  }
}

module.exports = new ExportService();
