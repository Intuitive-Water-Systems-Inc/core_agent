import os
import sys
import logging
import logging.handlers

def initialize_logger():
    homedir = os.path.expanduser("~")
    required_paths = [
        homedir+"/.core",
        homedir+"/.core/logs",
    ]

    for path in required_paths:
        if not os.path.exists(path):
            os.mkdir(path)

    logging_file_path = os.path.expanduser("~")+"/.core/logs/"

    logger = logging.getLogger("agent")
    logger.setLevel(logging.DEBUG)

    formatter = logging.Formatter("%(asctime)s --> %(filename)-14s %(levelname)-8s %(message) s")
    log_file_handler = logging.handlers.TimedRotatingFileHandler(filename=logging_file_path+"agent-log", when="midnight", backupCount=3)
    log_file_handler.setFormatter(formatter)

    logger.addHandler(log_file_handler)

    if bool(os.getenv("DEBUG", None)): 
        stream_handler = logging.StreamHandler(sys.stdout)
        stream_handler.setFormatter(formatter)
        logger.addHandler(stream_handler)

    return logger

def initialize_mqtt_logger():
    homedir = os.path.expanduser("~")
    required_paths = [
        homedir+"/.core",
        homedir+"/.core/logs",
    ]

    for path in required_paths:
        if not os.path.exists(path):
            os.mkdir(path)

    logging_file_path = os.path.expanduser("~")+"/.core/logs/"

    logger = logging.getLogger("mqtt")
    logger.setLevel(logging.DEBUG)

    formatter = logging.Formatter("%(message)s")
    log_file_handler = logging.handlers.TimedRotatingFileHandler(filename=logging_file_path+"mqtt-log", when="midnight", backupCount=14)
    log_file_handler.setFormatter(formatter)

    logger.addHandler(log_file_handler)

    if bool(os.getenv("DEBUG", None)): 
        stream_handler = logging.StreamHandler(sys.stdout)
        stream_handler.setFormatter(formatter)
        logger.addHandler(stream_handler)

    return logger
