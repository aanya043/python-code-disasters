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
    SONAR_PROJECT_KEY     = 'my-14848.linecount' 
    HADOOP_USER           = 'ananya'
    HADOOP_HOST           = '136.112.107.232'
    MR_REPO_URL         = 'https://github.com/aanya043/cloud-infra-jenkin-pipeline.git'
    MR_BRANCH           = 'main'
    MR_REPO_CREDENTIALS = ''   
  }

  triggers { githubPush() } 

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
          withEnv(['SONAR_SCANNER_OPTS=-Xmx4096m -XX:MaxMetaspaceSize=512m']) {  // bump to -Xmx3072m if needed
            script {
              def scannerHome = tool "${SONAR_SCANNER_TOOL}"
              sh """
                cd repo1
                ${scannerHome}/bin/sonar-scanner \
                  -Dsonar.host.url=${SONAR_HOST_URL} \
                  -Dsonar.login=${SONAR_AUTH_TOKEN}
              """
            }
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

    stage('Run Hadoop MapReduce (per-file line counts)') {
      steps {
        dir('repo2') {
          git url: 'https://github.com/aanya043/cloud-infra-jenkin-pipeline.git', branch: 'main'
        }

        sshagent(credentials: ['ananya-ssh']) {
          sh '''
            set -euxo pipefail
            REMOTE_DIR="/tmp/workspace-${BUILD_TAG}"

            # Fresh remote dir
            ssh -o StrictHostKeyChecking=no ${HADOOP_USER}@${HADOOP_HOST} "rm -rf ${REMOTE_DIR} && mkdir -p ${REMOTE_DIR}/src"

            # Send repo1 sources into REMOTE_DIR/src
            tar --exclude='./repo2' -C . -cf - . | ssh -o StrictHostKeyChecking=no ${HADOOP_USER}@${HADOOP_HOST} "tar -xf - -C ${REMOTE_DIR}/src"

            # Send only the runner bits from repo2 into REMOTE_DIR
            tar -C repo2 -cf - mapper.py reducer.py run_hadoop_linecount.sh | \
              ssh -o StrictHostKeyChecking=no ${HADOOP_USER}@${HADOOP_HOST} "tar -xf - -C ${REMOTE_DIR}"

            # Run on the master; tell script where the source files live
            ssh -o StrictHostKeyChecking=no ${HADOOP_USER}@${HADOOP_HOST} \
              "bash -lc 'cd ${REMOTE_DIR} && chmod +x mapper.py reducer.py run_hadoop_linecount.sh && SRC_DIR=src ./run_hadoop_linecount.sh'"
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
