pipeline {
  // Set per stage: the azurerm check needs python3, which the Terraform image lacks.
  agent none
  triggers {
    cron(env.BRANCH_NAME == 'main' ? 'H 6 * * 1' : '')
  }
  stages {
    stage('CI') {
      when {
        beforeAgent true
        allOf {
          not { buildingTag() }
          not { triggeredBy 'TimerTrigger' }
          anyOf {
            branch 'main'
            changeRequest()
          }
        }
      }
      agent {
        docker {
          image 'hashicorp/terraform:1.17.0'
          args '--entrypoint=""'
        }
      }
      stages {
        stage('Install tools') {
          steps {
            sh 'sh scripts/install-tools.sh'
          }
        }
        stage('Verify') {
          steps {
            sh 'sh scripts/verify.sh'
          }
        }
      }
    }
    stage('Release') {
      when {
        beforeAgent true
        buildingTag()
      }
      agent {
        docker {
          image 'hashicorp/terraform:1.17.0'
          args '--entrypoint=""'
        }
      }
      stages {
        stage('Install tools') {
          steps {
            sh 'sh scripts/install-tools.sh'
          }
        }
        stage('Release check') {
          steps {
            sh 'RELEASE_TAG="$TAG_NAME" sh scripts/release-check.sh'
          }
        }
        stage('Publish notes') {
          steps {
            archiveArtifacts artifacts: 'release-notes.md'
          }
        }
      }
    }
    // Jenkins has no issue tracker: a new azurerm version archives the report and marks
    // the build unstable, until .azurerm-reviewed-version is updated.
    stage('Check azurerm') {
      when {
        beforeAgent true
        triggeredBy 'TimerTrigger'
      }
      agent {
        docker {
          image 'python:3.13-alpine'
        }
      }
      steps {
        // catchError: a failure here must not skip the weekly scan below.
        catchError(buildResult: 'FAILURE', stageResult: 'FAILURE') {
          // The timer is weekly, so the first seven days hold its one run a month.
          sh '''
            rm -f azurerm-report.md
            [ "$(date +%d)" -le 7 ] || exit 0
            sh scripts/install-terraform.sh 1.17.0
            python3 scripts/check-registry.py
          '''
        }
        script {
          if (fileExists('azurerm-report.md')) {
            archiveArtifacts artifacts: 'azurerm-report.md'
            unstable('A new azurerm version needs review; see azurerm-report.md.')
          }
        }
      }
    }
    stage('Weekly scan') {
      when {
        beforeAgent true
        triggeredBy 'TimerTrigger'
      }
      agent {
        docker {
          image 'hashicorp/terraform:1.17.0'
          args '--entrypoint=""'
        }
      }
      steps {
        sh 'sh scripts/install-tools.sh'
        sh 'sh scripts/trivy-scan.sh HIGH'
      }
    }
  }
}
