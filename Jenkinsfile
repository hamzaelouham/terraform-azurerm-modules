pipeline {
  agent {
    docker {
      image 'hashicorp/terraform:1.17.0'
      args '--entrypoint=""'
    }
  }
  triggers {
    cron(env.BRANCH_NAME == 'main' ? 'H 6 * * 1' : '')
  }
  stages {
    stage('CI') {
      when {
        allOf {
          not { buildingTag() }
          not { triggeredBy 'TimerTrigger' }
          anyOf {
            branch 'main'
            changeRequest()
          }
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
      when { buildingTag() }
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
    stage('Weekly scan') {
      when { triggeredBy 'TimerTrigger' }
      steps {
        sh 'sh scripts/install-tools.sh'
        sh 'sh scripts/trivy-scan.sh LOW'
      }
    }
  }
}
