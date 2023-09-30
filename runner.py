from celery import Celery
import celeryconfig

app = Celery()
app.config_from_object('celeryconfig')

@app.task
def hello():
    return 'hello world'

@app.task
def add(x, y):
    return x + y

@app.task
def poll_event_and_take_action(event_object, action_object):
    event_happened = event_object.has_event_happened()

    if event_happened: 
      action_object.take_action()
