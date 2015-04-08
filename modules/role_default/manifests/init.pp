# default role
class role_default {

  include ::profile_common

  anchor{'role_default_first':}->
  Class['::profile_common']->
  anchor{'role_default_last':}

}