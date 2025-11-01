pipeline {
  agent {
      kubernetes {
        yaml """
          apiVersion: v1
          kind: Pod
          spec:
            containers:
            - name: jnlp
              image: jenkins/inbound-agent:latest
              resources:
                requests: {memory: "2Gi", cpu: "500m"}
                limits:   {memory: "5Gi", cpu: "1"}
          """
      }
    }

  environment {
    SONARQUBE_SERVER_NAME = 'SonarQube'
    SONAR_SCANNER_TOOL    = 'SonarQube-Scanner'
    SONAR_PROJECT_KEY     = 'my-14848-v1.linecount' 
    HADOOP_USER           = 'ananya'
    HADOOP_HOST           = '34.63.143.68'
    SRC_DIR = 'python'
  }

  triggers { githubPush() } 

  options {
    skipDefaultCheckout(true)
    quietPeriod(30)  
    }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        sh 'echo "Workspace:"; pwd; echo "---"; ls -la'
      }
    }

    stage('SonarQube Analysis') {
      when { changeset pattern: "python/**", comparator: "ANT" }
      steps {
        withSonarQubeEnv("${SONARQUBE_SERVER_NAME}") {
          script {
            def scannerHome = tool "${SONAR_SCANNER_TOOL}"
            sh """
              ${scannerHome}/bin/sonar-scanner \
                -Dsonar.projectKey=${SONAR_PROJECT_KEY} \
                -Dsonar.projectName=${SONAR_PROJECT_KEY} \
                -Dsonar.sources=. \
                -Dsonar.host.url=${SONAR_HOST_URL} \
                -Dsonar.login=${SONAR_AUTH_TOKEN}
            """
          }
        }
      }
    }

    stage('Quality Gate') {
      when { changeset pattern: "python/**", comparator: "ANT" }
      steps {
        timeout(time: 10, unit: 'MINUTES') {
          script {
            def qg = waitForQualityGate()
            echo "Quality Gate: ${qg.status}"
            if (qg.status != 'OK') { error "Quality Gate failed: ${qg.status}" }
          }
        }
      }
    }

    stage('Run Hadoop MapReduce (per-file line counts)') {
      when { changeset pattern: "python/**", comparator: "ANT" }
      steps {
        sshagent(credentials: ['ananya-ssh']) {
          sh '''
            set -euxo pipefail
            REMOTE_DIR="/tmp/workspace-${BUILD_TAG}"

            # Fresh remote dir on Dataproc master
            ssh -o StrictHostKeyChecking=no ${HADOOP_USER}@${HADOOP_HOST} "rm -rf ${REMOTE_DIR} && mkdir -p ${REMOTE_DIR}"

            # Send this repo to the master (exclude bulky/irrelevant dirs)
            tar --exclude='.git' --exclude='venv' --exclude='.venv' -C . -cf - . \
            | ssh -o StrictHostKeyChecking=no ${HADOOP_USER}@${HADOOP_HOST} "tar -xf - -C ${REMOTE_DIR}"

            # Sanity: confirm python files exist under SRC_DIR
            ssh -o StrictHostKeyChecking=no ${HADOOP_USER}@${HADOOP_HOST} \
              "find ${REMOTE_DIR}/${SRC_DIR} -type f -name '*.py' | head -n 20; \
               echo 'PY COUNT:' \$(find ${REMOTE_DIR}/${SRC_DIR} -type f -name '*.py' | wc -l)"

            # Run the job from repo root on the master
            ssh -o StrictHostKeyChecking=no ${HADOOP_USER}@${HADOOP_HOST} \
              "bash -lc 'cd ${REMOTE_DIR} && chmod +x mapper.py reducer.py run_hadoop_linecount.sh && SRC_DIR=${SRC_DIR} ./run_hadoop_linecount.sh'"


          '''
        }
      }
    }

    stage('Fetch & Display Results') {
      when { changeset pattern: "python/**", comparator: "ANT" }
      steps {
        sshagent(credentials: ['ananya-ssh']) {
          sh '''
            set -euxo pipefail
            REMOTE_DIR="/tmp/workspace-${BUILD_TAG}"
            ssh -o StrictHostKeyChecking=no ${HADOOP_USER}@${HADOOP_HOST} "ls -l ${REMOTE_DIR}/linecount.txt || true"
            scp -o StrictHostKeyChecking=no ${HADOOP_USER}@${HADOOP_HOST}:${REMOTE_DIR}/linecount.txt ./linecount.txt
          '''
        }
        echo "===== Hadoop Line Counts ====="
        sh 'set -e; test -s linecount.txt && cat linecount.txt || { echo "linecount.txt missing/empty"; exit 2; }'
        archiveArtifacts artifacts: 'linecount.txt', onlyIfSuccessful: true, allowEmptyArchive: false
      }
    }

  }

  post {
    always { echo 'Done.' }
    cleanup {
      sshagent(credentials: ['ananya-ssh']) {
        sh 'ssh -o StrictHostKeyChecking=no ${HADOOP_USER}@${HADOOP_HOST} "rm -rf /tmp/workspace-${BUILD_TAG}" || true'
      }
    }
  }
}
