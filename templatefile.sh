pipeline {
  agent {
     kubernetes {
      defaultContainer 'glams-jenkins-slave'
      yaml """
apiVersion: v1
kind: Pod
metadata:
  labels:
    name: glams
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: kubernetes.io/hostname
            operator: In
            values:
            - dev-k8s-hqwk03
  volumes:
    - name: docker-sock
      hostPath:
        path: /var/run/docker.sock
    - name: charts
      persistentVolumeClaim:
        claimName: test-dynamic-volume-claim
  containers:
  - name: glams-jenkins-slave
    image: registry.glams.local/glamsagent6
    imagePullPolicy: Always
    command:
    - cat
    tty: true
    volumeMounts:
     - mountPath: /var/run/docker.sock
       name: docker-sock
     - mountPath: /opt
       name: charts
"""
    }
}

options {
  buildDiscarder(logRotator(numToKeepStr: '10'))
  skipStagesAfterUnstable()
  durabilityHint('PERFORMANCE_OPTIMIZED')
  disableConcurrentBuilds()
  skipDefaultCheckout(true)
  overrideIndexTriggers(false)
}

triggers {
    cron('30 23 * * *') //run at 23:30:00 
}

stages {
  stage ('Checkout'){
    steps {
      script {
        //env.commit_id = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()
        env.commit_id = UUID.randomUUID().toString()
      }
     
		 withCredentials([file(credentialsId: 'dev-k8-hq', variable: 'SECRET')]) {
                    sh 'mkdir $HOME/.kube'
                    sh 'cat $SECRET > $HOME/.kube/config'
                    sh 'chown $(id -u):$(id -g) $HOME/.kube/config'
					
                }
                
		             checkout([$class: 'GitSCM', 
                    branches: [[name: 'master']], 
                    extensions: [],
                    userRemoteConfigs: [[credentialsId: 'GitAccess', url: 'https://surendra143245@bitbucket.org/perigorddata/activity-library-store.git']]])
                 

                //sed -i 's#installedactivities#getallactivities#g' Controllers/ActivityStoreController.cs
		dir('ActivityStore'){
        	sh '''
            	
				sed -i 's#http://localhost:9200/#http://elk-elasticsearch.test1.svc.cluster.local:9200/#g' appsettings.json 
				sed -i 's#http://localhost:3001#http://test1.glams.com/#g' appsettings.json 
                rm -rf Properties/launchSettings.json
                rm -rf ../ActivityStore.UnitTests
                
                
                dotnet publish -c Release -o out ActivityStore.csproj
                
                cat > Dockerfile <<EOL                
FROM  mcr.microsoft.com/dotnet/aspnet:6.0
WORKDIR /apps
COPY out .
EXPOSE 80
ENTRYPOINT ["dotnet", "ActivityStore.dll","--urls", "http://*:80","--no-https"]
EOL

docker build --no-cache -t tmp-${commit_id} .
docker tag tmp-${commit_id} registry.glams.local/test1-ativitystore:${commit_id}
docker push registry.glams.local/test1-ativitystore:${commit_id}
                        
            '''
            
            
        }

				sh 'cp -Rp /opt /test'
                
                sh '''
                    sed -i 's=imgpname=test1-ativitystore=g' charts/values.yaml 
                    sed -i 's=pname=ativitystore=g' /test/values.yaml
                    sed -i 's=pname=ativitystore=g' /test/Chart.yaml
                    sed -i 's=pname=ativitystore=g' /test/templates/_helpers.tpl
                    sed -i 's#--Probe#/swagger#g' /test/templates/deployment.yaml
                    sed -i 's=pname=ativitystore=g' /test/templates/deployment.yaml
                    sed -i 's=pname=ativitystore=g' /test/templates/service.yaml
                    sed -i 's=pname=ativitystore=g' /test/templates/hpa.yaml
                    sed -i 's=pname=ativitystore=g' /test/templates/serviceaccount.yaml
                    
                    sed -i 's=dname=$name=g' /test/templates/_helpers.tpl
                
                    rm -rf /test/nginx.conf
                    rm -rf /test/templates/pdeployment.yaml
                '''
        

  sh "helm upgrade --install activitystore -n test1 --set-string image.tag=${commit_id} --timeout 600s --wait /test || exit 1"
    }
  }
}
}
