import yaml

from receipt_parser_core.objectview import ObjectView


def read_config(config="config.yml"):
    """
    :param file: str
        Name of file to read
    :return: ObjectView
        Parsed config file
    """
    with open(config, 'rb') as stream:
        try:
            docs = yaml.safe_load(stream)
            return ObjectView(docs)
        except yaml.YAMLError as e:
            print(e)

def write_config(file="config.yml"):
    """
    :param config: ObjectView
        Config to write
    :param file: str
        Name of file to write
    :return: void
        Writes config to file
    """
    base_config = read_config()
    config = base_config.copy()
    with open(file, 'w') as outfile:
        yaml.dump(dict(config), outfile, default_flow_style=False)