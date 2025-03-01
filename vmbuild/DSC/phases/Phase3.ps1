configuration Phase3
{
    param
    (
        [Parameter(Mandatory)]
        [string]$DeployConfigPath,
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Admincreds
    )

    Set-ExecutionPolicy -ExecutionPolicy Bypass -Force
    Import-DscResource -ModuleName 'TemplateHelpDSC'
    Import-DscResource -ModuleName 'PSDesiredStateConfiguration', 'ComputerManagementDsc'
    Import-DscResource -ModuleName 'LanguageDsc'
    Import-DscResource -ModuleName 'CertificateDsc'

    # Read deployConfig
    $deployConfig = Get-Content -Path $DeployConfigPath | ConvertFrom-Json
    $DomainName = $deployConfig.parameters.domainName
    $NetBiosDomainName = $deployConfig.vmoptions.domainNetBiosName

    $l = $ConfigurationData.LocaleSettings

    Node $AllNodes.NodeName
    {
        $ThisVM = $deployConfig.virtualMachines | Where-Object { $_.vmName -eq $node.NodeName }

        # Install Language Packs
        if ($l -and $l.LanguageTag -and $l.LanguageTag -ne "en-US") {
            LanguagePack InstallLanguagePack {
                LanguagePackName     = $l.LanguageTag
                LanguagePackLocation = "C:\LanguagePacks"
            }

            Language ConfigureLanguage {
                IsSingleInstance     = "Yes"
                LocationID           = $l.LocationID
                MUILanguage          = $l.MUILanguage
                MUIFallbackLanguage  = $l.MUIFallbackLanguage
                SystemLocale         = $l.SystemLocale
                AddInputLanguages    = $l.AddInputLanguages
                RemoveInputLanguages = $l.RemoveInputLanguages
                UserLocale           = $l.UserLocale
                CopySystem           = $true
                CopyNewUser          = $true
                Dependson            = "[LanguagePack]InstallLanguagePack"
            }

            LocalConfigurationManager {
                RebootNodeIfNeeded = $true
                ActionAfterReboot  = "ContinueConfiguration"
                ConfigurationMode  = "ApplyAndAutoCorrect"
            }
        }

        $AddIISCert = $false
        # Install feature roles
        $featureRoles = @($ThisVM.role)
        if ($ThisVM.role -in "CAS", "Primary", "Secondary", "PassiveSite") {
            $featureRoles += "Site Server"
            $AddIISCert = $true
        }

        if ($ThisVM.installSUP -eq $true -and $ThisVM.role -ne "WSUS") {
            $featureRoles += "WSUS"
            $AddIISCert = $true
        }

        if ($ThisVM.installRP -eq $true) {
            $AddIISCert = $true
        }

        if ($ThisVM.installMP -eq $true) {
            $AddIISCert = $true
        }

        if ($ThisVM.installDP -eq $true) {
            $AddIISCert = $true
        }

        $DCVM = $deployConfig.virtualMachines | Where-Object { $_.role -eq "DC" }
        if (-not $DCVM.InstallCA) {
            $AddIISCert = $false
        }

        if (-not $deployConfig.cmOptions.UsePKI) {
            $AddIISCert = $false
        }

        WriteStatus AddLocalAdmin {
            Status = "Adding required accounts [$($ThisVM.thisParams.LocalAdminAccounts -join ',')] to Administrators group"
        }

        $addUserDependancy = @('[WriteStatus]AddLocalAdmin')
        $i = 0
        foreach ($user in $ThisVM.thisParams.LocalAdminAccounts) {
            $i++
            $DscNodeName = "AddADUserToLocalAdminGroup$($i)"
            AddUserToLocalAdminGroup "$DscNodeName" {
                Name              = $user
                NetbiosDomainName = $NetBiosDomainName
            }
            $addUserDependancy += "[AddUserToLocalAdminGroup]$DscNodeName"
        }

        WriteStatus InstallFeature {
            DependsOn = $addUserDependancy
            Status    = "Installing required windows features for role $featureRoles"
        }

        InstallFeatureForSCCM InstallFeature {
            Name      = "DummyName"
            Role      = $featureRoles
            DependsOn = "[WriteStatus]InstallFeature"
        }

        WriteStatus InstallDotNet {
            DependsOn = '[InstallFeatureForSCCM]InstallFeature'
            Status    = "Installing .NET 4.8"
        }

        InstallDotNet4 DotNet {
            DownloadUrl = $deployConfig.URLS.DotNet
            FileName    = "ndp48-x86-x64-allos-enu.exe"
            NetVersion  = "528040"
            Ensure      = "Present"
            DependsOn   = "[WriteStatus]InstallDotNet"
        }

        $nextDepend = "[InstallDotNet4]DotNet"
        if ($ThisVM.installSSMS -eq $true -or (($null -eq $ThisVM.installSSMS) -and $ThisVM.SQLVersion)) {
            # Check if false, for older configs that didn't have this prop

            $ssmsDownloadUrl = $deployConfig.URLS.SSMS
            if ($l.LanguageTag -ne "en-US") {
                $ssmsDownloadUrl = $ssmsDownloadUrl + "?clcid=" + $l.LanguageID
            }

            WriteStatus SSMS {
                DependsOn = $nextDepend
                Status    = "Downloading and installing SQL Management Studio"
            }

            InstallSSMS SSMS {
                DownloadUrl = $ssmsDownloadUrl
                Ensure      = "Present"
                DependsOn   = "[WriteStatus]SSMS"
            }

            $nextDepend = "[InstallSSMS]SSMS"
        }

        GpUpdate GpUpdate {
            Run = "True"
            DependsOn = $nextDepend
        }
        $nextDepend = "[GpUpdate]GpUpdate"

        if ($ThisVM.role -eq 'CAS' -or $ThisVM.role -eq "Primary" -or $ThisVM.role -eq "PassiveSite") {

            $prevDepend = $nextDepend

            WriteStatus ADKInstall {
                DependsOn = $nextDepend
                Status    = "Downloading and installing ADK"
            }

            InstallADK ADKInstall {
                ADKPath      = "C:\temp\adksetup.exe"
                ADKWinPEPath = "c:\temp\adksetupwinpe.exe"
                ADKDownloadPath = $deployConfig.URLS.ADK
                ADKWinPEDownloadPath = $deployConfig.URLS.ADKPE              
                Ensure       = "Present"
                DependsOn    = "[WriteStatus]ADKInstall"
            }
            

            $nextDepend = "[InstallADK]ADKInstall"
            if (-not $ThisVM.thisParams.ParentSiteServer -and $ThisVM.role -ne "PassiveSite" -and -not $ThisVM.hidden) {

                $CM = if ($deployConfig.cmOptions.version -eq "tech-preview") { "CMTP" } else { "CMCB" }
                $CMDownloadStatus = "Downloading Configuration Manager current branch (required baseline version)"
                if ($CM -eq "CMTP") {
                    $CMDownloadStatus = "Downloading Configuration Manager technical preview"
                }

                WriteStatus DownLoadSCCM {
                    DependsOn = $nextDepend
                    Status    = $CMDownloadStatus
                }

                DownloadSCCM DownLoadSCCM {
                    CM            = $CM
                    CMDownloadUrl = $ThisVM.thisParams.cmDownloadVersion.downloadUrl
                    Ensure        = "Present"
                    DependsOn     = $prevDepend
                }

                FileReadAccessShare CMSourceSMBShare {
                    Name      = $CM
                    Path      = "c:\$CM"
                    DependsOn = "[DownLoadSCCM]DownLoadSCCM"
                }
                $nextDepend = @($nextDepend, "[FileReadAccessShare]CMSourceSMBShare")
                #$nextDepend = "[FileReadAccessShare]CMSourceSMBShare"
            }
        }

        #add depend stuff
        #   if ($ThisVM.role -eq 'CAS' -or $ThisVM.role -eq "Primary" -or $ThisVM.role -eq "Secondary") {
        WriteStatus VCInstall {
            DependsOn = $nextDepend
            Status    = "Downloading and installing VC redist"
        }

        InstallVCRedist VCInstall {
            DependsOn = "[WriteStatus]VCInstall"
            Path      = "C:\temp\vc_redist.x64.exe"
            URL       = $deployConfig.URLS.VCredist
            Ensure    = "Present"
        }

        InstallVCRedist VCInstallx86 {
            DependsOn = "[InstallVCRedist]VCInstall"
            Path      = "C:\temp\vc_redist.x86.exe"
            URL       = $deployConfig.URLS.VCredistx86
            Ensure    = "Present"
        }

        WriteStatus SQLClientInstall {
            DependsOn = "[InstallVCRedist]VCInstallx86"
            Status    = "Downloading and installing SQL Client"
        }

        InstallSQLClient SQLClientInstall {
            DependsOn = "[WriteStatus]SQLClientInstall"
            URL       = $deployConfig.URLS.SQLClient
            Path      = "C:\temp\sqlncli.msi"
            Ensure    = "Present"
        }

        WriteStatus ODBCDriverInstall {
            DependsOn = "[InstallSQLClient]SQLClientInstall"
            Status    = "Downloading and installing ODBC driver"
        }

        InstallODBCDriver ODBCDriverInstall {
            DependsOn = "[WriteStatus]ODBCDriverInstall"
            URL       = $deployConfig.URLS.ODBC
            ODBCPath  = "C:\temp\msodbcsql.msi"
            Ensure    = "Present"
        }

        WriteStatus OleDbDriverInstall {
            DependsOn = "[InstallODBCDriver]ODBCDriverInstall"
            Status    = "Downloading and installing OleDB driver"
        }

        InstallOleDbDriver InstallOleDbDriver {
            DependsOn = "[WriteStatus]OleDbDriverInstall"
            URL       = $deployConfig.URLS.OleDB
            Path  = "C:\temp\msoledbsql.msi"
            Ensure    = "Present"
        }


        $nextDepend = "[InstallODBCDriver]ODBCDriverInstall"

        if ($AddIISCert) {


            WriteStatus RebootNow {
                Status    = "Rebooting to get Group Membership"
                DependsOn = $nextDepend
            }

            RebootNow RebootNow {
                FileName  = 'C:\Temp\IISGroupReboot.txt'
                DependsOn = $nextDepend
            }
            $nextDepend = "[RebootNow]RebootNow"

            WriteStatus RequestIISCerts {
                Status    = "Requesting IIS Certificate for PKI"
                DependsOn = $nextDepend
            }
            $subject = $ThisVM.vmName + "." + $DomainName
            $friendlyName = 'ConfigMgr WebServer Certificate'
            CertReq SSLCert {
                Subject             = $subject
                SubjectAltName      = "DNS=" + $subject + "&DNS=" + $($ThisVM.VmName)
                KeyLength           = '2048'
                Exportable          = $false
                ProviderName        = 'Microsoft RSA SChannel Cryptographic Provider'
                #OID                 = '1.3.6.1.5.5.7.3.1'
                #KeyUsage            = '0xa0'
                CertificateTemplate = 'ConfigMgrWebServerCertificate'
                AutoRenew           = $true
                FriendlyName        = $friendlyName
                #Credential          = $Credential
                #UseMachineContext   = $true
                KeyType             = 'RSA'
                RequestType         = 'CMC'
                DependsOn           = $nextDepend
            }
            $nextDepend = "[CertReq]SSLCert"

            WriteStatus AddIISCerts {
                Status    = "Adding IIS Certificate for PKI"
                DependsOn = $nextDepend
            }
            AddCertificateToIIS AddCert {
                FriendlyName = $friendlyName
                DependsOn    = $nextDepend
            }
            $nextDepend = "[AddCertificateToIIS]AddCert"

            if ($ThisVM.role -eq "Primary") {

                $friendlyName = 'ConfigMgr Client DistributionPoint Certificate'
                CertReq SSLCert2 {
                    Subject             = "Client DistributionPoint Cert"
                    #SubjectAltName      = "DNS=" + $subject
                    KeyLength           = '2048'
                    Exportable          = $true
                    ProviderName        = 'Microsoft RSA SChannel Cryptographic Provider'
                    #OID                 = '1.3.6.1.5.5.7.3.1'
                    #KeyUsage            = '0xa0'
                    CertificateTemplate = 'ConfigMgrClientDistributionPointCertificate'
                    AutoRenew           = $true
                    FriendlyName        = $friendlyName
                    #Credential          = $Credential
                    #UseMachineContext   = $true
                    KeyType             = 'RSA'
                    RequestType         = 'CMC'
                    DependsOn           = $nextDepend
                }
                $nextDepend = "[CertReq]SSLCert2"

                CertificateExport SSLCert {
                    Type         = 'PFX'
                    FriendlyName = $friendlyName
                    Path         = 'c:\temp\ConfigMgrClientDistributionPointCertificate.pfx'
                    Password     = $Admincreds
                    DependsOn    = $nextDepend
                }
                $nextDepend = "[CertificateExport]SSLCert"
            }
        }


        #  }

        WriteStatus Complete {
            DependsOn = $nextDepend
            Status    = "Complete!"
        }

    }
}