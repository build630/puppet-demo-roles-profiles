# foo role
class role_bar {

  include ::profile_common

  anchor{'role_default_first':}->
  Class['::profile_common']->
  anchor{'role_default_last':}

}