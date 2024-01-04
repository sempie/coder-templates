# AWS Instance Type Available
This template provides an example where an array of instance types is used.  The available instance types for a given availability zone are queried, and if the user's preference is unavailable, it falls back to the next smallest instance.

This is useful in cases when using large GPU instances in an availability zone that has limited availability.

