$StampEndpoint = 'east.azurestack.contoso.com'
$OutputDirectory = "$ENV:USERPROFILE\Documents\AzureStackCSR"

# Generate certificate signing requests for deployment:
New-AzsHubDeploymentCertificateSigningRequest -StampEndpoint $StampEndpoint -OutputRequestPath $OutputDirectory

# Generate certificate requests for other Azure Stack Hub services use
# App Services
New-AzsHubAppServicesCertificateSigningRequest -StampEndpoint $StampEndpoint -OutputRequestPath $OutputDirectory

# DBAdapter
New-AzsHubDBAdapterCertificateSigningRequest -StampEndpoint $StampEndpoint -OutputRequestPath $OutputDirectory

# EventHubs
New-AzsHubEventHubsCertificateSigningRequest -StampEndpoint $StampEndpoint -OutputRequestPath $OutputDirectory

# IoTHub
New-AzsHubIotHubCertificateSigningRequest -StampEndpoint $StampEndpoint -OutputRequestPath $OutputDirectory

# Alternatively, for Dev/Test environments, to generate a single certificate request with multiple Subject Alternative Names add -RequestType SingleCSR parameter and value
New-AzsHubDeploymentCertificateSigningRequest -StampEndpoint $StampEndpoint -OutputRequestPath $OutputDirectory -RequestType SingleCSR