# Various Yosemite-specific sensor data. Includes data from the profile (distance) detection, reflector detection, and
# gap sensor.
std_msgs/Header header
bool front_profile_detected
bool rear_profile_detected
bool front_reflector_detected
bool rear_reflector_detected
bool gap_detected
bool emergency_stop_active
float64 profile_detection_distance