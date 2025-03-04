require 'json'

module Fluent
  class DockerFormatOutput < Output
    Fluent::Plugin.register_output('docker_format', self)
    config_param :tag, :string
    config_param :container_id, :string
    config_param :docker_containers_path, :string, :default => '/var/lib/docker/containers'

    def configure(conf)
      super
      @id_to_docker_cfg = {}
    end

    def emit(tag, es, chain)
      es.each do |time,record|
        router.emit(interpolate_tag(tag), time, format_record(tag, record))
      end

      chain.next
    end

    private

    def interpolate(tag, str)
      tag_parts = tag.split('.')

      str.gsub(/\$\{tag_parts\[(\d+)\]\}/) { |m| tag_parts[$1.to_i] }
    end

    def interpolate_tag(tag)
      id = interpolate(tag, @container_id)

      container_name = get_container_name(id)
      @tag.gsub(/\$\{name\}/, container_name || id)
      @tag.gsub(/\$\{container_name\}/, container_name || id)

      image_name = get_image_name(id)
      image_name.gsub!(/\:.*$/,'') if image_name  # strip the docker tag
      @tag.gsub(/\$\{image_name\}/, image_name || id)
    end

    def get_docker_cfg_from_id(id)
      begin
        config_path = "#{@docker_containers_path}/#{id}/config.json"
        if not File.exists?(config_path)
          config_path = "#{@docker_containers_path}/#{id}/config.v2.json"
        end
        docker_cfg = JSON.parse(File.read(config_path))
        container_name = docker_cfg['Name']
      rescue
        docker_cfg = nil
      end
      docker_cfg
    end 

    def get_container_name(id)
      @id_to_docker_cfg[id] = get_docker_cfg_from_id(id) unless @id_to_docker_cfg.has_key? id
      if @id_to_docker_cfg[id] == nil 
        container_name = nil
      else 
        container_name = @id_to_docker_cfg[id]['Name'][1..-1]
      end
      container_name
    end
    alias_method :get_name, :get_container_name

    def get_image_name(id)
      @id_to_docker_cfg[id] = get_docker_cfg_from_id(id) unless @id_to_docker_cfg.has_key? id
      if @id_to_docker_cfg[id] == nil 
        image_name = nil
      else 
        image_name = @id_to_docker_cfg[id]['Config']['Image'].dup
      end
      image_name
    end

    def get_env_variable(id, variable)
      env_value = nil
      @id_to_docker_cfg[id] = get_docker_cfg_from_id(id) unless @id_to_docker_cfg.has_key? id
      if @id_to_docker_cfg[id] == nil 
        env_value = nil
      else 
        envs = @id_to_docker_cfg[id]['Config']['Env']
        envs.each{
          |env|
          envString = env.split("=")
          if envString.length == 2 && envString[0] == variable 
            env_value = envString[1]
            break
          end
        }
      end
      env_value
    end

    def get_label(id, key) 
      label_value = nil
      @id_to_docker_cfg[id] = get_docker_cfg_from_id(id) unless @id_to_docker_cfg.has_key? id
      if @id_to_docker_cfg[id] == nil 
        label_value = nil
      else 
        label_value = @id_to_docker_cfg[id]['Config']["Labels"][key]
      end
      label_value
    end

    def format_record(tag, record)
      id = interpolate(tag, @container_id)
      record['container_id'] = id
      record['container_name'] = get_container_name(id) || "<unknown>"
      record['image_name'] = get_image_name(id) || "<unknown>"
      service_id = get_label(id, "com.docker.compose.project.working_dir") #change this to service id label once it's finalized
      if service_id != nil
        record['service_id'] = service_id
      end
      record
    end

  end
end
