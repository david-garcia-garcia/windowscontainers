$global:ErrorActionPreference = 'Stop'

#########################################################
## New Relic Infrastructure agent Setup
##########################################################

# ¿Porqué neceistamos un monitor de infraestructura en un contendor?
# Porque NO sirve solo para monitorizar constantes vitales (que es algo que deja de tener sentido)
# en un contenedor y ahora var por otros sitios, sino que además permite
# * Capturar y enviar a NR métricas de Perfrmon. Esto es crítico para entornos con IIS (colas de peticiones, etc.)
# * Capturar y enviar a NR entradsa del Event Viewer
# * Capturar y enviar a NR logs de aplicaciones


# Instalar monitorización de New Relic
choco upgrade newrelic-infra -y --version=1.49.1 --no-progress;

# El servicio para por defecto y con arranque manual. Porque no sirve de nada
# que arranque si no le llegan los parámetros de configuración, que vienen
# por variables de entorno.
Stop-Service -Name "newrelic-infra";
Set-Service -Name "newrelic-infra" -StartupType Disabled;

Get-ChildItem -Path $env:TEMP, 'C:\Windows\Temp' -Recurse | Remove-Item -Force -Recurse;
Remove-Item -Path "$env:TEMP\*" -Recurse -Force;
