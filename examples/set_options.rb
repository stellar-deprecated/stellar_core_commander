use_manual_close

account :scott
account :bartek
create_account :scott
create_account :bartek

close_ledger

kp = Stellar::KeyPair.random

set_inflation_dest :scott, :bartek
set_flags :scott, [:auth_required_flag]
set_master_signer_weight :scott, 2
set_thresholds :scott, low: 0, medium: 2, high: 2
set_thresholds :scott, high: 1
set_home_domain :scott, "nullstyle.com"
add_signer :scott, kp, 1

close_ledger

clear_flags :scott, [:auth_required_flag]
remove_signer :scott, kp
