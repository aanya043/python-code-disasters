pipeline {
  agent any

  environment {
    // --- Sonar & Hadoop ---
    SONARQUBE_SERVER_NAME = 'SonarQube'
    SONAR_SCANNER_TOOL    = 'SonarQube-Scanner'
    SONAR_PROJECT_KEY     = 'my-14848.linecount'   // analysis key for repo1
    HADOOP_USER           = 'ananya'
    HADOOP_HOST           = '136.112.107.232'

    // --- Repo 2 (mapper/reducer/scripts) ---
    MR_REPO_URL         = 'https://github.com/aanya043/cloud-infra-jenkin-pipeline.git'
    MR_BRANCH           = 'main'
    MR_REPO_CREDENTIALS = ''   // leave empty (public); set to a Jenkins cred ID if private
  }

  triggers { githubPush() }   // webhook on repo1 only

  stages {
    stage('Checkout repo1 (this repo) & repo2') {
      steps {
        // repo1 = the SCM of this job (python-code-disasters)
        dir('repo1') {
          checkout scm
          sh 'echo "[repo1] PWD=$PWD"; ls -la'
        }

        // repo2 = cloud-infra-jenkin-pipeline (mapper/reducer + run_hadoop_linecount.sh)
        dir('repo2') {
          script {
            def cfg = [
              $class: 'GitSCM',
              branches: [[name: "*/${env.MR_BRANCH}"]],
              userRemoteConfigs: [[url: env.MR_REPO_URL]]
            ]
            if (env.MR_REPO_CREDENTIALS?.trim()) {
              cfg.userRemoteConfigs = [[url: env.MR_REPO_URL, credentialsId: env.MR_REPO_CREDENTIALS]]
            }
            checkout(cfg)
          }
          sh 'echo "[repo2] PWD=$PWD"; ls -la'
        }
      }
    }

    stage('SonarQube Analysis (repo1)') {
      steps {
        withSonarQubeEnv("${SONARQUBE_SERVER_NAME}") {
          script {
            def scannerHome = tool "${SONAR_SCANNER_TOOL}"
            sh """
              cd repo1
              ${scannerHome}/bin/sonar-scanner \
                -Dsonar.projectKey=${SONAR_PROJECT_KEY} \
                -Dsonar.projectName=${SONAR_PROJECT_KEY} \
                -Dsonar.sources=. \
                -Dsonar.exclusions="**/*.ipynb,**/*.csv,**/*.tsv,**/*.parquet,**/*.png,**/*.jpg,**/*.gif,**/*.zip,**/*.gz,**/*.tar,**/__pycache__/**,**/*.pyc,**/.venv/**,**/venv/**" \
                -Dsonar.host.url=${SONAR_HOST_URL} \
                -Dsonar.login=${SONAR_AUTH_TOKEN}
            """
          }
        }
      }
    }

    stage('Quality Gate') {
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

    stage('Run Hadoop MapReduce using repo2') {
      steps {
        sshagent(credentials: ['ananya-ssh']) {
          sh '''
            set -euxo pipefail
            REMOTE_DIR="/tmp/workspace-${BUILD_TAG}"

            # Create remote workspace
            ssh -o StrictHostKeyChecking=no ${HADOOP_USER}@${HADOOP_HOST} "mkdir -p ${REMOTE_DIR}"

            # Copy only repo2 content (mapper.py, reducer.py, run_hadoop_linecount.sh)
            ( cd repo2 && tar -cf - . ) | \
              ssh -o StrictHostKeyChecking=no ${HADOOP_USER}@${HADOOP_HOST} "tar -xf - -C ${REMOTE_DIR}"

            # Verify files on VM
            ssh -o StrictHostKeyChecking=no ${HADOOP_USER}@${HADOOP_HOST} "set -eux; ls -la ${REMOTE_DIR}"

            # Ensure script present
            ssh -o StrictHostKeyChecking=no ${HADOOP_USER}@${HADOOP_HOST} "test -f ${REMOTE_DIR}/run_hadoop_linecount.sh || (echo 'run_hadoop_linecount.sh not found!' >&2; exit 2)"

            # Run the job (script should: use python3, set STREAMING_JAR, copy /tmp/results.txt -> linecount.txt)
            ssh -o StrictHostKeyChecking=no ${HADOOP_USER}@${HADOOP_HOST} \
              "bash -lc 'cd ${REMOTE_DIR} && chmod +x mapper.py reducer.py run_hadoop_linecount.sh && WORKDIR=${REMOTE_DIR} ./run_hadoop_linecount.sh'"
          '''
        }
      }
    }

    stage('Fetch & Display Results') {
      steps {
        sshagent(credentials: ['ananya-ssh']) {
          sh '''
            set -euxo pipefail
            REMOTE_DIR="/tmp/workspace-${BUILD_TAG}"
            ssh -o StrictHostKeyChecking=no ${HADOOP_USER}@${HADOOP_HOST} "ls -la ${REMOTE_DIR} || true"
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
