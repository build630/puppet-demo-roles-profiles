# foo role
class role_foo {

  include ::profile_common

  anchor{'role_default_first':}->
  Class['::profile_common']->
  anchor{'role_default_last':}

}