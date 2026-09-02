# Deploy SignalApp to AWS EC2 from Windows (run after security group allows SSH)
$ErrorActionPreference = "Stop"

$Key = "$env:USERPROFILE\.ssh\scalptrack.pem"
$Host = "ubuntu@13.235.102.43"
$Repo = "/opt/signalapp/repo"

if (-not (Test-Path $Key)) {
    Write-Error "SSH key not found: $Key"
}

Write-Host "Testing SSH..."
ssh -i $Key -o StrictHostKeyChecking=no -o ConnectTimeout=15 $Host "echo SSH OK"
if ($LASTEXITCODE -ne 0) {
    Write-Error @"
SSH failed. In AWS Console:
  EC2 -> Security Groups -> your instance SG -> Inbound rules:
    - SSH (22) from YOUR IP
    - Custom TCP 8000 from 0.0.0.0/0
  Ensure instance state is 'running'
"@
}

Write-Host "Copying .env (SmartAPI keys)..."
scp -i $Key -o StrictHostKeyChecking=no backend\.env "${Host}:${Repo}/backend/.env"

Write-Host "Deploying on server..."
ssh -i $Key -o StrictHostKeyChecking=no $Host @"
set -e
cd $Repo && git pull --ff-only
cd backend && bash scripts/deploy_aws.sh
"@

Write-Host "Done. API: http://13.233.102.43:8000/health"
