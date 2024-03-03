$global:ErrorActionPreference = 'Stop';

Write-Host "`n---------------------------------------"
Write-Host " Deploying IIS perfmon integration scripts"
Write-Host "-----------------------------------------`n"

$serviceName = 'newrelic-infra'
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue;

if ($service.Length -eq 0) {
	throw "This script needs the New Relic Infrastructure service to be already deployed.";
}