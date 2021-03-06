function Dump-Domains {
    <#
    .SYNOPSIS

        Dump all the domains and trust relationships.

    .DESCRIPTION

        This cmdlet allows a normal user, without any special permissions, to
        dump all the domains and respective trust relationships.

    .PARAMETER ResultFile

        File that will be written with the domains.

    .LINK

        https://www.serializing.me/tags/active-directory/

    .EXAMPLE 
 
        Dump-Domains -DomainFile .\Domains.xml

    .NOTE

        Function: Dump-Domains
        Author: Duarte Silva (@serializingme)
        License: GPLv3
        Required Dependencies: None
        Optional Dependencies: None
        Version: 1.0.0
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $True)]
        [String]$ResultFile
    )

    function Date-ToString {
        param(
            [DateTime]$Date,
            [Bool]$InUTC = $False
        )

        [String]$format = 'yyyy-MM-ddTHH:mm:ss.fffffffZ'

        if ($InUTC) {
            return $Date.ToString($format)
        }
        else {
            return $Date.ToUniversaltime().ToString($format)
        }
    }

    function Process-Trusted {
        param(
            [Xml.XmlWriter]$ResultFileWriter,
            [Collections.Hashtable]$Trusted
        )

        $ResultFileWriter.WriteStartElement('Trusted')

        if (-not [String]::IsNullOrEmpty($Trusted.Name)) {
            $ResultFileWriter.WriteAttributeString('Name', $Trusted.Name)
        }
        if (-not [String]::IsNullOrEmpty($Trusted.DNS)) {
            $ResultFileWriter.WriteAttributeString('DNS', $Trusted.DNS)
        }

        $ResultFileWriter.WriteEndElement()
    }

    function Process-Domain {
        param(
            [Xml.XmlWriter]$ResultFileWriter,
            [Collections.Hashtable]$Domain
        )

        Write-Verbose ('Processing domain {0}' -f $Domain.Name)

        [DirectoryServices.DirectoryEntry]$DomainRoot = $Null
        [DirectoryServices.DirectorySearcher]$RelatedSearch = $Null

        try {
            $ResultFileWriter.WriteStartElement('Domain')
            $ResultFileWriter.WriteAttributeString('Name', $Domain.Name)

            if (-not [String]::IsNullOrEmpty($Domain.DNS)) {
                $ResultFileWriter.WriteAttributeString('DNS', $Domain.DNS)
            }
            if ($Domain.Created -ne $Null) {
                $ResultFileWriter.WriteAttributeString('Created',
                        (Date-ToString -Date $Domain.Created -InUTC $True))
            }
            if ($Domain.Changed -ne $Null) {
                $ResultFileWriter.WriteAttributeString('Changed',
                        (Date-ToString -Date $Domain.Changed -InUTC $True))
            }

            # Get the domain trust relationships.
            $DomainRoot = New-Object DirectoryServices.DirectoryEntry @(
                    'LDAP://{0}' -f $Domain.Name )

            $RelatedSearch = New-Object DirectoryServices.DirectorySearcher @(
                    $DomainRoot, '(objectclass=trusteddomain)' )
            $RelatedSearch.PageSize = 500
            $RelatedSearch.PropertiesToLoad.Add('flatname') | Out-Null
            $RelatedSearch.PropertiesToLoad.Add('name') | Out-Null

            [Collections.Hashtable]$Trusted = @{
                'Name' = $Null;
                'DNS' = $Null;
            }

            $RelatedSearch.FindAll() | ForEach-Object {
                if (($_.Properties.flatname -ne $Null) -and
                        (-not [String]::IsNullOrEmpty($_.Properties.flatname.Item(0)))) {
                    $Trusted.Name = $_.Properties.flatname.Item(0).ToUpper()
                }
                if (($_.Properties.name -ne $Null) -and
                        (-not [String]::IsNullOrEmpty($_.Properties.name.Item(0)))) {
                    $Trusted.DNS = $_.Properties.name.Item(0).ToLower()
                }

                Process-Trusted -ResultFileWriter $ResultFileWriter -Trusted $Trusted

                # Make sure the hastable properties are null since it is being
                # reused.
                $Trusted.Name = $Null
                $Trusted.DNS = $Null
            }

            $ResultFileWriter.WriteEndElement()
        }
        catch {
            Write-Warning ('Failed to process domain {0} ({1})' -f $DomainName, $DomainDNS)
        }
        finally {
            if ($RelatedSearch -ne $Null) {
                $RelatedSearch.Dispose()
            }
            if ($DomainRoot -ne $Null) {
                $DomainRoot.Dispose()
            }
        }
    }

    function Process-Domains {
        param(
            [Xml.XmlWriter]$ResultFileWriter
        )

        [DirectoryServices.DirectoryEntry]$MainRoot = $Null
        [DirectoryServices.DirectoryEntry]$PartitionsRoot = $Null
        [DirectoryServices.DirectorySearcher]$DomainSearch = $Null

        try {
            $MainRoot = New-Object DirectoryServices.DirectoryEntry @(
                    'LDAP://RootDSE' )

            $PartitionsRoot = New-Object DirectoryServices.DirectoryEntry @(
                    'LDAP://CN=Partitions,{0}' -f $MainRoot.Get('configurationNamingContext') )

            $DomainSearch = New-Object DirectoryServices.DirectorySearcher @(
                    $PartitionsRoot, '(&(objectcategory=crossref)(netbiosname=*))' )
            $DomainSearch.PageSize = 500
            $DomainSearch.PropertiesToLoad.Add('dnsroot') | Out-Null
            $DomainSearch.PropertiesToLoad.Add('ncname') | Out-Null
            $DomainSearch.PropertiesToLoad.Add('netbiosname') | Out-Null
            $DomainSearch.PropertiesToLoad.Add('whencreated') | Out-Null
            $DomainSearch.PropertiesToLoad.Add('whenchanged') | Out-Null
            
            [Collections.Hashtable]$Domain = @{
                'Name' = $Null;
                'DNS' = $Null;
                'Created' = $Null;
                'Changed' = $Null;
            }

            $DomainSearch.FindAll() | ForEach-Object {
                $Domain.Name = $_.Properties.netbiosname.Item(0)

                if (($_.Properties.dnsroot -ne $Null) -and
                        (-not [String]::IsNullOrEmpty($_.Properties.dnsroot.Item(0)))) {
                    $Domain.DNS = $_.Properties.dnsroot.Item(0).ToLower()
                }     
                if (($_.Properties.whencreated -ne $Null) -and
                        ($_.Properties.whencreated.Item(0) -ne $Null)) {
                    $Domain.Created = $_.Properties.whencreated.Item(0)
                }
                if (($_.Properties.whenchanged -ne $Null) -and
                        ($_.Properties.whenchanged.Item(0) -ne $Null)) {
                    $Domain.Changed = $_.Properties.whenchanged.Item(0)
                }

                Process-Domain -ResultFileWriter $ResultFileWriter -Domain $Domain

                # Make sure the hastable properties are null since it is being
                # reused.
                $Domain.DNS = $Null
                $Domain.Created = $Null
                $Domain.Changed = $Null
            }
        }
        finally {
            if ($DomainSearch -ne $Null) {
                $DomainSearch.Dispose()
            }
            if ($PartitionsRoot -ne $Null) {
                $PartitionsRoot.Dispose()
            }
            if ($MainRoot -ne $Null) {
                $MainRoot.Dispose()
            }
        }
    }

    [IO.FileStream]$ResultFileStream = $Null
    [Xml.XmlWriter]$ResultFileWriter = $Null

    try {
        [IO.FileInfo]$ResultFileInfo = New-Object IO.FileInfo @( $ResultFile )

        if ($ResultFileInfo.Exists -eq $True) {
            Write-Warning 'The file to save the scan results already exists and it will be overwritten'
        }

        # Instantiate the XML stream and writer.
        $ResultFileStream = New-Object IO.FileStream -ArgumentList @(
                $ResultFileInfo.FullName, [IO.FileMode]::Create, [IO.FileAccess]::Write )

        [Xml.XmlWriterSettings]$ResultXmlSettings = New-Object Xml.XmlWriterSettings
        $ResultXmlSettings.Indent = $True

        $ResultFileWriter = [Xml.XmlWriter]::Create($ResultFileStream, $ResultXmlSettings)
        $ResultFileWriter.WriteStartElement('Domains')
        $ResultFileWriter.WriteStartElement('Start')
        $ResultFileWriter.WriteAttributeString('Time', (Date-ToString -Date (Get-Date)))
        $ResultFileWriter.WriteEndElement()

        Process-Domains -ResultFileWriter $ResultFileWriter

        $ResultFileWriter.WriteStartElement('End')
        $ResultFileWriter.WriteAttributeString('Time', (Date-ToString -Date (Get-Date)))
        $ResultFileWriter.WriteEndElement()
    }
    finally {    
        if ($ResultFileWriter -ne $Null) {
            $ResultFileWriter.Close()
        }
        if ($ResultFileStream -ne $Null) {
            $ResultFileStream.Close()
        }
    }
}
