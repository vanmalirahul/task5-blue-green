pipeline {
    agent any

    // ── PARAMETERS — shown as a form before each build ─────────────
    parameters {
        string(
            name: 'APP_VERSION',
            defaultValue: '',
            description: 'Version tag (e.g. v2.1) — leave empty to use build number'
        )
        choice(
            name: 'ENVIRONMENT',
            choices: ['staging', 'production'],
            description: 'Target environment'
        )
        booleanParam(
            name: 'SKIP_SMOKE_TEST',
            defaultValue: false,
            description: 'WARNING: Only skip smoke test for debugging'
        )
    }

    // ── ENVIRONMENT VARIABLES — available in all stages ──────────────
    environment {
        APP_SERVER         = '192.168.1.102'
        JENKINS_SERVER     = '192.168.1.101'
        GIT_REPO           = 'https://github.com/vanmalirahul/task5-blue-green.git'
        ANSIBLE_HOST_KEY_CHECKING = 'False'
        ANSIBLE_FORCE_COLOR       = '1'
        // Build version: use param if given, else auto-generate from build number
        VERSION = "${params.APP_VERSION ?: 'v1.' + BUILD_NUMBER}"
    }

    // ── OPTIONS — pipeline-wide settings ─────────────────────────────
    options {
        timeout(time: 30, unit: 'MINUTES')           // fail if pipeline takes > 30 min
        buildDiscarder(logRotator(numToKeepStr: '20')) // keep last 20 builds
        disableConcurrentBuilds()                       // CRITICAL: never run 2 blue-green deploys at once!
        timestamps()                                     // add timestamps to every log line
    }

    stages {

        // ────────────────────────────────────────────────
        // STAGE 1: CHECKOUT
        // ────────────────────────────────────────────────
        stage('Checkout') {
            steps {
                echo "=== Checking out code from GitHub ==="
                git branch: 'main', url: "${GIT_REPO}"
                sh """
                    echo "Git commit: \$(git rev-parse --short HEAD)"
                    echo "Branch:     \$(git branch --show-current)"
                    echo "Version:    ${VERSION}"
                    echo "Build #:    ${BUILD_NUMBER}"
                """
            }
        }

        // ────────────────────────────────────────────────
        // STAGE 2: VALIDATE
        // ────────────────────────────────────────────────
        stage('Validate Ansible') {
            steps {
                echo "=== Validating Ansible playbooks and roles ==="
                sh """
                    # Check YAML syntax for ALL playbooks
                    ansible-playbook ansible/site.yml \
                        -i ansible/inventory/hosts \
                        --syntax-check \
                        -e "app_version=${VERSION}"
                    echo "✅ Syntax check passed"

                    # Verify we can reach the app server
                    ansible appservers -i ansible/inventory/hosts -m ping
                    echo "✅ App server 192.168.1.102 is reachable"
                """
            }
        }

        // ────────────────────────────────────────────────
        // STAGE 3: CHECK CURRENT SLOT STATUS
        // ────────────────────────────────────────────────
        stage('Check Current State') {
            steps {
                echo "=== Reading current Blue-Green state ==="
                sh """
                    # Read current active slot from the server
                    ACTIVE=\$(ssh -i /var/lib/jenkins/.ssh/id_rsa \
                        -o StrictHostKeyChecking=no \
                        ansible-svc@${APP_SERVER} \
                        "cat /etc/bluegreen/active_slot")

                    echo "Currently LIVE:  \$ACTIVE"
                    if [ "\$ACTIVE" = "blue" ]; then
                        echo "Will deploy to:  GREEN (port 8081)"
                    else
                        echo "Will deploy to:  BLUE (port 8080)"
                    fi

                    # Check what version is live right now
                    echo ""
                    echo "--- Current slot status ---"
                    curl -s http://${APP_SERVER}/slot-status || echo "(slot-status endpoint not ready)"
                """
            }
        }

        // ────────────────────────────────────────────────
        // STAGE 4: PRODUCTION APPROVAL GATE
        // (only for production environment)
        // ────────────────────────────────────────────────
        stage('Approval Gate') {
            when {
                expression { return params.ENVIRONMENT == 'production' }
            }
            steps {
                timeout(time: 10, unit: 'MINUTES') {
                    // Pipeline PAUSES here — a human must click Proceed
                    input(
                        message: "Deploy ${VERSION} to PRODUCTION?",
                        ok: 'Yes — Deploy to Production',
                        submitter: 'admin,lead-dev',  // only these users can approve
                        parameters: [
                            booleanParam(name: 'CONFIRMED', defaultValue: false,
                                         description: 'I confirm this is ready for production')
                        ]
                    )
                }
            }
        }

        // ────────────────────────────────────────────────
        // STAGE 5: BLUE-GREEN DEPLOY
        // ────────────────────────────────────────────────
        stage('Blue-Green Deploy') {
            steps {
                echo "=== Starting Blue-Green Deployment — Version ${VERSION} ==="
                sh """
                    ansible-playbook \
                        -i ansible/inventory/hosts \
                        ansible/site.yml \
                        -e "app_version=${VERSION}" \
                        -e "build_number=${BUILD_NUMBER}" \
                        -v
                """
            }
        }

        // ────────────────────────────────────────────────
        // STAGE 6: SMOKE TEST
        // ────────────────────────────────────────────────
        stage('Smoke Test') {
            when {
                expression { return !params.SKIP_SMOKE_TEST }
            }
            steps {
                echo "=== Running smoke tests on http://${APP_SERVER} ==="
                sh """
                    # Test 1: App responds on port 80
                    echo "Test 1: HTTP 200 on port 80..."
                    HTTP_STATUS=\$(curl -s -o /dev/null -w "%{http_code}" \
                        --max-time 10 http://${APP_SERVER})
                    if [ "\$HTTP_STATUS" != "200" ]; then
                        echo "❌ FAILED: Got HTTP \$HTTP_STATUS (expected 200)"
                        exit 1
                    fi
                    echo "✅ PASSED: HTTP 200"

                    # Test 2: Slot status endpoint works
                    echo "Test 2: Slot status endpoint..."
                    SLOT_RESP=\$(curl -s http://${APP_SERVER}/slot-status)
                    echo "Slot status: \$SLOT_RESP"
                    echo "✅ PASSED: Slot status responding"

                    # Test 3: Active slot header is present
                    echo "Test 3: X-Active-Slot header..."
                    HEADER=\$(curl -sI http://${APP_SERVER} | grep -i 'X-Active-Slot')
                    echo "Header: \$HEADER"
                    echo "✅ PASSED: Active slot header present"

                    echo ""
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                    echo "✅ ALL SMOKE TESTS PASSED"
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                """
            }
        }

        // ────────────────────────────────────────────────
        // STAGE 7: DEPLOYMENT REPORT
        // ────────────────────────────────────────────────
        stage('Deployment Report') {
            steps {
                sh """
                    echo ""
                    echo "╔══════════════════════════════════════╗"
                    echo "║       DEPLOYMENT COMPLETE            ║"
                    echo "╠══════════════════════════════════════╣"
                    echo "║ Version:  ${VERSION}"
                    echo "║ Server:   ${APP_SERVER}"
                    echo "║ URL:      http://${APP_SERVER}"
                    echo "║ Build #:  ${BUILD_NUMBER}"
                    echo "╚══════════════════════════════════════╝"
                """
            }
        }
    }

    // ── POST — always runs regardless of success/failure ─────────────
    post {
        failure {
            echo '❌ Pipeline FAILED — triggering automatic rollback...'
            sh """
                ansible-playbook \
                    -i ansible/inventory/hosts \
                    ansible/rollback.yml \
                    -v || echo 'WARNING: Rollback also failed — manual intervention needed!'
            """
        }
        success {
            echo "✅ Deployment of ${VERSION} succeeded!"
        }
        always {
            // Archive deployment info for audit trail
            sh """
                echo "Build: ${BUILD_NUMBER} | Version: ${VERSION} | Result: ${currentBuild.currentResult}" \
                >> /var/log/jenkins-deploy.log || true
            """
        }
    }
}
