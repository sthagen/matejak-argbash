#!/bin/bash

# ARG_POSITIONAL_SINGLE([act-ion], [], [foo])
# ARG_TYPE_GROUP_SET([act], [ACTION], [act-ion], [foo,baz,bar bar,[foo,baz]], [index])
# ARG_HELP([Testing program])
# ARGBASH_GO

# opening escape square bracket: [

# Now we take the parsed data and assign them no nice-looking variable names,
# sometimes after a basic validation
echo "ACT=$_arg_act_ion,IDX=$_arg_act_ion_index,"

# closing escape square bracket: ]

