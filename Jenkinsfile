pipeline {
    agent {
        kubernetes {
            yamlFile 'scripts/runtime/harness/jenkins-agent-pod.yaml'
            defaultContainer 'jnlp'
        }
    }

    options {
        timeout(time: 120, unit: 'MINUTES')
        ansiColor('xterm')
    }

    parameters {
        string(
            name: 'BITBUCKET_PROJECT',
            defaultValue: 'LCP',
            description: 'Bitbucket project key (e.g. LCP). Required unless BITBUCKET_REPO is set.'
        )
        string(
            name: 'BITBUCKET_REPO',
            defaultValue: 'lcp-core-device-state-service',
            description: 'Specific repo slug to process (e.g. lcp-core-device-state-service). Leave blank to process all repos in the project.'
        )
        string(
            name: 'GOAL',
            defaultValue: 'Fetch the SF tickets data from jira for this repo and pick one and fix.',
            description: 'The task for the coding agent to carry out on each repo.'
        )
        booleanParam(
            name: 'DRY_RUN',
            defaultValue: false,
            description: 'If true, the agent runs but does not push branches or raise PRs.'
        )
        booleanParam(
            name: 'RUN_PREFLIGHT_TESTS',
            defaultValue: false,
            description: 'If true, runs the GPU check and harness inference test stage.'
        )
        booleanParam(
            name: 'ENABLE_DD_METRICS',
            defaultValue: true,
            description: 'If true, emits CI run metrics to Datadog.'
        )
        choice(
            name: 'AGENT_HARNESS',
            choices: ['pi.dev', 'opencode', 'claude'],
            description: 'Coding harness to run.'
        )
    }

    environment {
        BITBUCKET_PROJECT = "${params.BITBUCKET_PROJECT}"
        BITBUCKET_REPO    = "${params.BITBUCKET_REPO}"
        GOAL              = "${params.GOAL}"
        DRY_RUN           = "${params.DRY_RUN}"
        AGENT_HARNESS     = "${params.AGENT_HARNESS}"
        ENABLE_DD_METRICS = "${params.ENABLE_DD_METRICS}"
        DD_SITE           = "datadoghq.com"
    }

    stages {
        stage('Validate Parameters') {
            steps {
                script {
                    if (!params.BITBUCKET_PROJECT?.trim() && !params.BITBUCKET_REPO?.trim()) {
                        error('BITBUCKET_PROJECT is required when BITBUCKET_REPO is not specified.')
                    }
                    if (!params.GOAL?.trim()) {
                        error('GOAL parameter must not be empty.')
                    }
                    echo "Project : ${params.BITBUCKET_PROJECT ?: '<all repos>'}"
                    echo "Repo    : ${params.BITBUCKET_REPO ?: '<all>'}"
                    echo "Goal    : ${params.GOAL}"
                    echo "Dry run : ${params.DRY_RUN}"
                    if (!['claude', 'opencode', 'pi.dev'].contains(params.AGENT_HARNESS)) {
                        error("AGENT_HARNESS must be one of: claude, opencode, pi.dev")
                    }
                    echo "Harness : ${params.AGENT_HARNESS}"
                }
            }
        }

        stage('Warm Model Server') {
            steps {
                container('model-server') {
                    sh -x 'scripts/platform/jenkins/warm-model-server.sh'
                }
            }
        }

        // stage('Wait for Model Server') {
        //     steps {
        //         container('model-server') {
        //             sh 'scripts/platform/jenkins/wait-for-model-server.sh'
        //         }
        //     }
        // }

        // stage('Preflight / Tests') {
        //     when {
        //         expression { return params.RUN_PREFLIGHT_TESTS == true }
        //     }
        //     stages {
        //         stage('GPU Check') {
        //             steps {
        //                 container('model-server') {
        //                     sh 'nvidia-smi'
        //                 }
        //             }
        //         }

        //         stage('Test Harness Inference') {
        //             steps {
        //                 script {
        //                     def runPreflight = {
        //                         parallel(
        //                             inference: {
        //                                 container('coding-agent') {
        //                                     sh 'METRICS_DIR="/metrics/${AGENT_HARNESS}" scripts/platform/jenkins/run-harness-preflight.sh'
        //                                 }
        //                             },
        //                             metrics: {
        //                                 container('model-server') {
        //                                     sh 'RUN_TYPE=preflight scripts/platform/jenkins/collect-metrics.sh --metrics-dir "/metrics/${AGENT_HARNESS}"'
        //                                 }
        //                             }
        //                         )
        //                     }
        //                     if (params.ENABLE_DD_METRICS) {
        //                         withCredentials([
        //                             string(credentialsId: 'DATADOG_API_KEY', variable: 'DD_API_KEY')
        //                         ]) {
        //                             runPreflight()
        //                         }
        //                     } else {
        //                         runPreflight()
        //                     }
        //                 }
        //             }
        //         }
        //     }
        // }

    //     stage('Setup') {
    //         steps {
    //             container('coding-agent') {
    //                 withCredentials([
    //                     usernamePassword(credentialsId: 'BITBUCKET_API_KEY', usernameVariable: 'BITBUCKET_USER', passwordVariable: 'BITBUCKET_API_KEY')
    //                 ]) {
    //                     sh 'scripts/runtime/harness/setup.sh'
    //                 }
    //             }
    //         }
    //     }

    //     stage('Enumerate Repos') {
    //         steps {
    //             container('coding-agent') {
    //                 withCredentials([
    //                     usernamePassword(credentialsId: 'BITBUCKET_API_KEY', usernameVariable: 'BITBUCKET_USER', passwordVariable: 'BITBUCKET_API_KEY')
    //                 ]) {
    //                     script {
    //                         def repos = sh(
    //                             script: 'scripts/runtime/harness/enumerate-repos.sh "${BITBUCKET_PROJECT}"',
    //                             returnStdout: true
    //                         ).trim()

    //                         if (!repos) {
    //                             error("No repositories found in project '${params.BITBUCKET_PROJECT}'")
    //                         }

    //                         env.REPO_LIST = repos
    //                         echo "Repos to process:\n${repos}"
    //                     }
    //                 }
    //             }
    //         }
    //     }

    //     stage('Run Agent') {
    //         steps {
    //             script {
    //                 def runAgentParallel = {
    //                     parallel(
    //                         agent: {
    //                             container('coding-agent') {
    //                                 script {
    //                                     try {
    //                                         withCredentials([
    //                                             usernamePassword(credentialsId: 'BITBUCKET_API_KEY', usernameVariable: 'BITBUCKET_USER',  passwordVariable: 'BITBUCKET_API_KEY'),
    //                                             string(credentialsId: 'JIRA_API_TOKEN', variable: 'JIRA_API_TOKEN'),
    //                                             string(credentialsId: 'SONAR_AUTH_TOKEN', variable: 'SONAR_AUTH_TOKEN')
    //                                         ]) {
    //                                             def repoList = env.REPO_LIST.split('\n')
    //                                             for (repo in repoList) {
    //                                                 repo = repo.trim()
    //                                                 if (!repo) continue
    //                                                 echo ">>> Processing repo: ${repo}"
    //                                                 sh "scripts/runtime/harness/run-harness-on-repo.sh '${env.BITBUCKET_PROJECT}' '${repo}'"
    //                                             }
    //                                         }
    //                                     } finally {
    //                                         sh 'mkdir -p /metrics/agent && touch /metrics/agent/DONE'
    //                                     }
    //                                 }
    //                             }
    //                         },
    //                         metrics: {
    //                             container('model-server') {
    //                                 sh 'RUN_TYPE=agent scripts/platform/jenkins/collect-metrics.sh --metrics-dir /metrics/agent'
    //                             }
    //                         }
    //                     )
    //                 }
    //                 if (params.ENABLE_DD_METRICS) {
    //                     withCredentials([
    //                         string(credentialsId: 'DATADOG_API_KEY', variable: 'DD_API_KEY')
    //                     ]) {
    //                         runAgentParallel()
    //                     }
    //                 } else {
    //                     runAgentParallel()
    //                 }
    //             }
    //         }
    //     }
    // }

    // post {
    //     always {
    //         container('jnlp') {
    //             sh 'scripts/platform/jenkins/post-build-artifacts.sh'
    //             archiveArtifacts artifacts: 'pr-summary.txt', allowEmptyArchive: true
    //             archiveArtifacts artifacts: 'agent-logs/**/*', allowEmptyArchive: true
    //             archiveArtifacts artifacts: 'metrics-artifacts/**/*', allowEmptyArchive: true
    //             script {
    //                 env.BUILD_RESULT = currentBuild.currentResult ?: 'SUCCESS'
    //             }
    //             script {
    //                 if (params.ENABLE_DD_METRICS) {
    //                     withCredentials([
    //                         string(credentialsId: 'DATADOG_API_KEY', variable: 'DD_API_KEY')
    //                     ]) {
    //                         sh '''
    //                             set +e
    //                             scripts/platform/jenkins/export-run-metrics-to-datadog.sh "${WORKSPACE}"
    //                             rc=$?
    //                             if [ "$rc" -ne 0 ]; then
    //                                 echo "WARNING: Datadog export failed (non-fatal), exit=${rc}"
    //                             fi
    //                             set -e
    //                         '''
    //                     }
    //                 } else {
    //                     echo "Datadog export disabled for this build (ENABLE_DD_METRICS=false)."
    //                 }
    //             }
    //             script {
    //                 if (fileExists('metrics-artifacts/agent/metrics-summary.html')) {
    //                     publishHTML(target: [
    //                         allowMissing:          false,
    //                         alwaysLinkToLastBuild: true,
    //                         keepAll:               true,
    //                         reportDir:             'metrics-artifacts/agent',
    //                         reportFiles:           'metrics-summary.html',
    //                         reportName:            'Agent Run GPU/CPU Metrics'
    //                     ])
    //                 }
    //                 if (fileExists("metrics-artifacts/${env.AGENT_HARNESS}/metrics-summary.html")) {
    //                     publishHTML(target: [
    //                         allowMissing:          false,
    //                         alwaysLinkToLastBuild: true,
    //                         keepAll:               true,
    //                         reportDir:             "metrics-artifacts/${env.AGENT_HARNESS}",
    //                         reportFiles:           'metrics-summary.html',
    //                         reportName:            'Preflight GPU/CPU Metrics'
    //                     ])
    //                 }
    //             }
    //         }
    //     }
    //     failure {
    //         echo 'Pipeline failed. Check the agent logs above for details.'
    //     }
    }
}
