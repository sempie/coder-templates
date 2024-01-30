# AWS Capacity Reservation
This template provides an example for AWS EC2 instance capacity reservation.

This is useful in cases where instance types are not always available in a given availability zone and must be reserved to guarantee a workspace will operate.

## Steps

### Create Capacity Reservation
1. run capacity reservation terraform from ./reservation/
2. note the capacity reservation id to use in template

### Configure Template
Install template and add AWS credentials and capacity reservation id 
