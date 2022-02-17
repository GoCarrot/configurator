# frozen_string_literal: true

# Copyright 2021 Teak.io, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'lifecycle_vm/op_base'

module ConfigOMat
  module Op
    class RefreshProfile < LifecycleVM::OpBase
      reads :profile_defs, :client_id, :applying_profile, :appconfig_client, :secretsmanager_client, :secrets_loader_memory
      writes :applying_profile, :secrets_loader_memory

      def call
        profile_name = applying_profile.name
        profile_version = applying_profile.version
        definition = profile_defs[profile_name]
        request = {
          application: definition.application, environment: definition.environment,
          configuration: definition.profile, client_id: client_id,
          client_configuration_version: profile_version
        }

        response =
          begin
            appconfig_client.get_configuration(request)
          rescue StandardError => e
            error profile_name, e
            nil
          end

        return if response.nil? || errors?
        loaded_version = response.configuration_version

        if loaded_version == profile_version
          logger&.warning(
            :no_update,
            name: profile_name, version: profile_version
          )
          return
        end

        logger&.notice(
          :updated_profile,
          name: profile_name, previous_version: profile_version, new_version: loaded_version
        )

        profile = LoadedAppconfigProfile.new(
          profile_name, loaded_version, response.content.read, response.content_type
        )

        loaded_secrets = nil

        if !profile.secret_defs.empty?
          self.secrets_loader_memory ||= ConfigOMat::SecretsLoader::Memory.new(secretsmanager_client: secretsmanager_client)
          secrets_loader_memory.update_secret_defs_to_load(profile.secret_defs.values)

          vm = ConfigOMat::SecretsLoader::VM.new(secrets_loader_memory).call

          if vm.errors?
            error :"#{profile_name}_secrets", vm.errors
            return
          end

          loaded_secrets = secrets_loader_memory.loaded_secrets.each_with_object({}) do |(key, value), hash|
            hash[value.name] = value
          end
        end

        self.applying_profile = LoadedProfile.new(profile, loaded_secrets)
      end
    end
  end
end
