#!/usr/bin/python
import RPi.GPIO as GPIO
import time
import paho.mqtt.client as mqttClient

def on_connect(client, userdata, flags, rc):
    if rc == 0:
        print("Connected to broker")
        global Connected                #Use global variable
        Connected = True                #Signal connection
    else:
        print("Connection failed")
        Connected = False   #global variable for the state of the connection


def distancesensortomqtt(TRIGGERIO,ECHOIO,TOPIC,BROKER,USERNAME,PASSWORD):
    GPIO.setmode(GPIO.BOARD)
    PIN_TRIGGER = TRIGGERIO
    PIN_ECHO = ECHOIO
    GPIO.setup(PIN_TRIGGER, GPIO.OUT)
    GPIO.setup(PIN_ECHO, GPIO.IN)
    GPIO.output(PIN_TRIGGER, GPIO.LOW)
    pulse_start_time = 0
    pulse_end_time  =  0
    print("Waiting for sensor to settle")
    time.sleep(2)
    print("Calculating distance")
    GPIO.output(PIN_TRIGGER, GPIO.HIGH)
    time.sleep(0.00001)
    GPIO.output(PIN_TRIGGER, GPIO.LOW)
    while GPIO.input(PIN_ECHO)==0:
        pulse_start_time = time.time()
    while GPIO.input(PIN_ECHO)==1:
        pulse_end_time = time.time()
    pulse_duration = pulse_end_time - pulse_start_time
    distance = round(pulse_duration * 17150, 2)
    print("Distance:",distance,"cm")
    GPIO.cleanup()
    broker_address= BROKER
    port = 1883
    user = USERNAME
    password = PASSWORD
    client = mqttClient.Client("Python")
    client.username_pw_set(user, password=password)
    client.on_connect= on_connect
    client.connect(broker_address, port=port)
    client.loop_start()
    client.publish(TOPIC,distance,retain=False)


distancesensortomqtt(7,11,"rpi/distance/sensor1","smartwala.azim.network",'username','password')
distancesensortomqtt(38,40,"rpi/distance/sensor2","smartwala.azim.network",'username','password')
