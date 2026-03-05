const fs = require('fs');
const path = require('path');
const { v4: uuidv4 } = require('uuid');
const { formatISO } = require('date-fns');

const MODELS_DIR = './data';
const ARCHIVE_DIR = './data/archive';
const REGISTRY_FILE = './data/model_registry.json';

class ModelVersioning {
  
  /**
   * Get currently active model (Liso et al. 2018 PEM physics model)
   */
  getActiveModel() {
    const registry = this.getRegistry();
    const activeEntry = registry.find(m => m.status === 'active');
    
    if (!activeEntry) {
      throw new Error('No active model found');
    }
    
    const modelPath = path.join(MODELS_DIR, \);
    const model = JSON.parse(fs.readFileSync(modelPath, 'utf8'));
    
    return {
      ...model,
      metadata: activeEntry
    };
  }
  
  /**
   * Get all models (active + archived) with version history
   */
  getModelHistory() {
    const registry = this.getRegistry();
    return registry.map(entry => ({
      version: entry.version,
      status: entry.status,
      date: entry.date,
      error: entry.error,
      replacementReason: entry.replacementReason,
      trainingDataRange: entry.trainingDataRange,
      samples: entry.samples,
      RMSE: entry.RMSE,
      MAE: entry.MAE,
      MAPE: entry.MAPE,
      R2: entry.R2,
      purityCheck: entry.purityCheck
    }));
  }
  
  /**
   * Get specific archived model by version
   */
  getArchivedModel(version) {
    const fileName = \model_\_archive.json\;
    const filePath = path.join(ARCHIVE_DIR, fileName);
    
    if (!fs.existsSync(filePath)) {
      throw new Error(\Model \ not found\);
    }
    
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  }
  
  /**
   * COMPARISON PROTOCOL: Compare new model against current active
   * Requirements: 5% MAPE improvement, p<0.05, O₂ purity ≥99.5%
   */
  validateAndCompareModel(newModelData, uploadReason) {
    const activeModel = this.getActiveModel();
    const comparison = this._performComparison(activeModel, newModelData);
    
    // Check 5% improvement threshold (MAPE)
    const mapeImprovement = ((activeModel.metadata.MAPE - comparison.newMAPE) / 
                             activeModel.metadata.MAPE) * 100;
    
    // Statistical significance test (p < 0.05 required)
    const pValue = this._calculatePValue(activeModel, newModelData);
    
    // Safety check: O₂ purity ≥99.5%
    const purityValid = newModelData.validation?.purity >= 99.5;
    
    const canReplace = 
      mapeImprovement >= 5.0 && 
      pValue < 0.05 && 
      purityValid;
    
    return {
      canReplace,
      currentModel: {
        version: activeModel.metadata.version,
        RMSE: activeModel.metadata.RMSE,
        MAE: activeModel.metadata.MAE,
        MAPE: activeModel.metadata.MAPE,
        R2: activeModel.metadata.R2,
        parameters: activeModel.parameters.pem
      },
      newModel: {
        RMSE: comparison.newRMSE,
        MAE: comparison.newMAE,
        MAPE: comparison.newMAPE,
        R2: comparison.newR2,
        parameters: newModelData.parameters?.pem || {}
      },
      metrics: {
        mapeImprovement: mapeImprovement.toFixed(2) + '%',
        pValue: pValue.toFixed(4),
        purityCheck: \\% (Required: ≥99.5%)\,
        samplesUsed: newModelData.samples || 0
      },
      recommendations: this._generateRecommendations(canReplace, mapeImprovement, pValue, purityValid),
      uploadReason
    };
  }
  
  /**
   * APPROVE model replacement & archive current
   * Increments version (v1.0→v1.1 or v1.9→v2.0) and archives with timestamp
   */
  promoteModelToActive(newModelData, uploadReason) {
    const activeModel = this.getActiveModel();
    const registry = this.getRegistry();
    
    // Archive current active model with timestamp
    const datePart = activeModel.metadata.date.split('T')[0];
    const archiveFileName = \model_\_\.json\;
    const archivePath = path.join(ARCHIVE_DIR, archiveFileName);
    fs.writeFileSync(archivePath, JSON.stringify(activeModel, null, 2));
    
    console.log(\✓ Archived model \ → \\);
    
    // Mark old model as archived in registry
    const oldEntry = registry.find(m => m.status === 'active');
    oldEntry.status = 'archived';
    oldEntry.archiveDate = formatISO(new Date());
    
    // Calculate new version (v1.0→v1.1, v1.9→v2.0)
    const newVersion = this._incrementVersion(activeModel.metadata.version);
    
    // Create new model entry with full metadata
    const newModelEntry = {
      id: uuidv4(),
      version: newVersion,
      fileName: 'initial_model.json',
      status: 'active',
      date: formatISO(new Date()),
      error: newModelData.validation?.error || 0,
      RMSE: newModelData.validation?.RMSE || 0,
      MAE: newModelData.validation?.MAE || 0,
      MAPE: newModelData.validation?.MAPE || 0,
      R2: newModelData.validation?.R2 || 0,
      replacementReason: uploadReason,
      trainingDataRange: newModelData.trainingDataRange || 'Unknown',
      samples: newModelData.samples || 0,
      purityCheck: newModelData.validation?.purity || 0,
      pemParameters: newModelData.parameters?.pem || {}
    };
    
    // Save new active model to data/initial_model.json
    fs.writeFileSync(
      path.join(MODELS_DIR, 'initial_model.json'),
      JSON.stringify(newModelData, null, 2)
    );
    
    // Update registry with new entry
    registry.push(newModelEntry);
    this.saveRegistry(registry);
    
    return {
      success: true,
      newVersion,
      message: \Model promoted to \. Previous \ archived as \\,
      newModelEntry
    };
  }
  
  /**
   * COMPARE two models side-by-side (for thesis/analysis)
   */
  compareModels(version1, version2) {
    const model1 = version1 === 'active' 
      ? this.getActiveModel()
      : this.getArchivedModel(version1);
    
    const model2 = version2 === 'active'
      ? this.getActiveModel()
      : this.getArchivedModel(version2);
    
    return {
      model1: {
        version: model1.metadata?.version || version1,
        RMSE: model1.validation?.RMSE,
        MAE: model1.validation?.MAE,
        MAPE: model1.validation?.MAPE,
        R2: model1.validation?.R2,
        purityCheck: model1.validation?.purity,
        parameters: model1.parameters?.pem
      },
      model2: {
        version: model2.metadata?.version || version2,
        RMSE: model2.validation?.RMSE,
        MAE: model2.validation?.MAE,
        MAPE: model2.validation?.MAPE,
        R2: model2.validation?.R2,
        purityCheck: model2.validation?.purity,
        parameters: model2.parameters?.pem
      },
      improvements: {
        RMSE: ((model1.validation?.RMSE - model2.validation?.RMSE) / model1.validation?.RMSE * 100).toFixed(2) + '%',
        MAPE: ((model1.validation?.MAPE - model2.validation?.MAPE) / model1.validation?.MAPE * 100).toFixed(2) + '%',
        R2: (model2.validation?.R2 - model1.validation?.R2).toFixed(4)
      }
    };
  }
  
  // ============ PRIVATE HELPER METHODS ============
  
  getRegistry() {
    if (!fs.existsSync(REGISTRY_FILE)) {
      return [];
    }
    return JSON.parse(fs.readFileSync(REGISTRY_FILE, 'utf8'));
  }
  
  saveRegistry(registry) {
    fs.writeFileSync(REGISTRY_FILE, JSON.stringify(registry, null, 2));
  }
  
  _performComparison(model1, model2) {
    // Calculate error metrics for new model
    return {
      newRMSE: model2.validation?.RMSE || 0,
      newMAE: model2.validation?.MAE || 0,
      newMAPE: model2.validation?.MAPE || 0,
      newR2: model2.validation?.R2 || 0
    };
  }
  
  _calculatePValue(model1, model2) {
    // Mock statistical significance test
    // In production: use proper t-test or ANOVA
    const rmseRatio = model2.validation?.RMSE / model1.validation?.RMSE || 1;
    return Math.max(0.01, 1 - rmseRatio);
  }
  
  _generateRecommendations(canReplace, improvement, pValue, purityValid) {
    const recommendations = [];
    
    if (improvement < 5.0) {
      recommendations.push(\❌ MAPE improvement only \% (Required: ≥5%)\);
    }
    if (pValue >= 0.05) {
      recommendations.push(\❌ Statistical significance p=\ (Required: <0.05)\);
    }
    if (!purityValid) {
      recommendations.push('❌ O₂ purity does not meet ≥99.5% requirement (Safety violation)');
    }
    
    if (canReplace) {
      recommendations.push('✅ Model meets ALL replacement criteria - safe to deploy');
    }
    
    return recommendations;
  }
  
  _incrementVersion(currentVersion) {
    // v1.0 → v1.1 → v1.2 ... v1.9 → v2.0
    const parts = currentVersion.replace('v', '').split('.');
    let major = parseInt(parts[0]);
    let minor = parseInt(parts[1]) || 0;
    
    minor++;
    if (minor >= 10) {
      major++;
      minor = 0;
    }
    
    return \\.\\;
  }
}

module.exports = new ModelVersioning();
