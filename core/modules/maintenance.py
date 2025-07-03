import os
import json
import datetime

def send_status(token, client, status, configs): 
    topic = f"device/{token}/hive"
    message = json.dumps({
        "type": "update_status",
        "status": status
    })
    configs["mqtt-logger"].debug({
                "date": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"), 
                "type": "PUBLISH", 
                "topic": topic, 
                "message": message})
    client.publish(
        topic, 
        message
    )
    
    

def update_service(service, beta_enabled, logger, mqtt_client, token, configs):
    logger.info(f"[MAINTENANCE] Updating {service} service")

    send_status(token, mqtt_client, f"download_{service}", configs)

    commands = [
        f"cd /opt/sixfab/core/{service}",
        "sudo git reset --hard HEAD",
        "sudo git fetch",
        "sudo git checkout dev" if beta_enabled else "sudo git checkout master",
        "sudo git pull",
        f"source /opt/sixfab/core/{service}/venv/bin/activate"
        "pip3 install -U -r requirements.txt"
        "deactivate"
    ]

    os.system(" && ".join(commands))
    logger.info(f"[MAINTENANCE] Updated {service} source")

    logger.info(f"[MAINTENANCE] Restarting {service} service")
    send_status(token, mqtt_client, f"restart_{service}", configs)

    os.system(f"sudo systemctl restart core_{service}")

def restart_service(service_name):
    os.system(f"sudo systemctl restart core_{service_name}")


def main(data, configs, mqtt_client):
    logger = configs["logger"]
    logger.info("[MAINTENANCE] Running maintenance")

    beta_enabled = data.get("beta", False)
    services_to_update = data.get("update", [])
    services_to_restart = data.get("restart", [])
    
    if not services_to_restart and not services_to_update:
        return # nothing to do :(

    if "manager" in services_to_update:
        update_service("manager", beta_enabled, logger, mqtt_client, configs["token"], configs)

    elif "manager" in services_to_restart:
        logger.info("[MAINTENANCE] Restarting manager service")
        restart_service("core_manager")

    if "agent" in services_to_update:
        update_service("agent", beta_enabled, logger, mqtt_client, configs["token"], configs)

    elif "agent" in services_to_restart:
        logger.info("[MAINTENANCE] Restarting agent service")
        restart_service("core_agent")