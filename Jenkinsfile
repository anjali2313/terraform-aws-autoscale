pipeline {
    agent any

    environment {
        AWS_ACCESS_KEY_ID     = credentials('sec-key')   // Jenkins credential ID for AWS access key
        AWS_SECRET_ACCESS_KEY = credentials('new-id')   // Jenkins credential ID for AWS secret key
        AWS_DEFAULT_REGION    = 'ap-northeast-1'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Terraform Init') {
            steps {
                sh 'terraform init'
            }
        }

        stage('Terraform Plan') {
            steps {
                sh 'terraform plan -out=tfplan'
            }
        }

        stage('Terraform Apply') {
            steps {
                sh 'terraform apply -auto-approve tfplan'
            }
        }
    }

    post {
        always {
            echo "Terraform pipeline finished."
        }
        success {
            echo "Infrastructure provisioned successfully!"
        }
        failure {
            echo "Terraform failed. Check the logs."
        }
    }
}
