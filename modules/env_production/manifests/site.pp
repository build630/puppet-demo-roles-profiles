# silence a deprecation warning
if versioncmp($::puppetversion,'3.6.1') >= 0 {
  $allow_virtual_packages = hiera('allow_virtual_packages',false)
  Package {
    allow_virtual => $allow_virtual_packages,
  }
}

# set default properties for files
File{
  owner => 'root',
  group => 'root',
  mode  => '0644',
}