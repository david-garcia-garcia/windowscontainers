Import-Module Log-Rotate;
Log-Rotate -Config "c:\logrotate\Log-Rotate.conf" -State "c:\logrotate\Log-Rotate.status" -Verbose;