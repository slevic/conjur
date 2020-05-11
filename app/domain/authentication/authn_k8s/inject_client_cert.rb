require 'command_class'

module Authentication
  module AuthnK8s

    Log ||= LogMessages::Authentication::AuthnK8s
    Err ||= Errors::Authentication::AuthnK8s
    # Possible Errors Raised:
    # CSRIsMissingSpiffeId, CertInstallationError

    InjectClientCert ||= CommandClass.new(
      dependencies: {
        logger:                 Rails.logger,
        resource_class:         Resource,
        conjur_ca_repo:         Repos::ConjurCA,
        kubectl_exec:           KubectlExec,
        validate_pod_request:   ValidatePodRequest.new,
        audit_event:            ::Authentication::AuditEvent.new
      },
      inputs: %i(conjur_account service_id csr host_id_prefix)
    ) do

      def call
        update_csr_common_name
        validate
        install_signed_cert
      rescue => e
        audit_failure(e)
        raise e
      end

      private

      def validate
        # We validate the CSR first since the pod_request uses its values
        validate_csr

        @validate_pod_request.(pod_request: pod_request)
      end

      def install_signed_cert
        pod_namespace = spiffe_id.namespace
        pod_name = spiffe_id.name
        @logger.debug(Log::CopySSLToPod.new(pod_namespace, pod_name))

        resp = @kubectl_exec.new.copy(
          k8s_object_lookup: k8s_object_lookup,
          pod_namespace: pod_namespace,
          pod_name: pod_name,
          container: container_name,
          path: "/etc/conjur/ssl/client.pem",
          content: cert_to_install.to_pem,
          mode: 0o644
        )
        validate_cert_installation(resp)
      end

      # In the old version of the authn-client we assumed that the host is under the "apps" policy branch.
      # Now we send the host-id in 2 parts:
      #   suffix - the host id
      #   prefix - the policy id
      # We update the CSR's common_name to have the full host-id. This way, the validation
      # that happens in the "authenticate" request will work, as the signed certificate
      # contains the full host-id.
      def update_csr_common_name
        prefix = @host_id_prefix.nil? || @host_id_prefix.empty? ? apps_host_id_prefix : @host_id_prefix
        full_host_name = prefix + "." + smart_csr.common_name

        Rails.logger.debug(Log::SetCommonName.new(full_host_name))
        smart_csr.common_name = full_host_name
      end

      def apps_host_id_prefix
        "host.conjur.authn-k8s.#{@service_id}.apps"
      end

      def pod_request
        PodRequest.new(
          service_id: @service_id,
          k8s_host: k8s_host,
          spiffe_id: spiffe_id
        )
      end

      def k8s_host
        @k8s_host ||= Authentication::AuthnK8s::K8sHost.from_csr(
          account: @conjur_account,
          service_name: @service_id,
          csr: smart_csr
        )
      end

      def host_id
        k8s_host.conjur_host_id
      end

      def spiffe_id
        @spiffe_id ||= SpiffeId.new(smart_csr.spiffe_id)
      end

      def pod
        @pod ||= k8s_object_lookup.pod_by_name(
          spiffe_id.name, spiffe_id.namespace
        )
      end

      def host
        @host ||= @resource_class[host_id]
      end

      def validate_csr
        raise Err::CSRIsMissingSpiffeId unless smart_csr.spiffe_id
      end

      def smart_csr
        @smart_csr ||= ::Util::OpenSsl::X509::SmartCsr.new(@csr)
      end

      def common_name
        @common_name ||= CommonName.new(smart_csr.common_name)
      end

      def validate_cert_installation(resp)
        error_stream = resp[:error]
        return if error_stream.nil? || error_stream.empty?
        raise Err::CertInstallationError, cert_error(error_stream)
      end

      # In case there's a blank error message...
      def cert_error(msg)
        return 'The server returned a blank error message' if msg.blank?
        msg.to_s
      end

      def ca_for_webservice
        @conjur_ca_repo.ca(webservice.resource_id)
      end

      def webservice
        ::Authentication::Webservice.new(
          account: @conjur_account,
          authenticator_name: 'authn-k8s',
          service_id: @service_id
        )
      end

      def cert_to_install
        ca_for_webservice.signed_cert(
          smart_csr,
          subject_altnames: [spiffe_id.to_altname]
        )
      end

      def k8s_object_lookup
        @k8s_object_lookup ||= K8sObjectLookup.new(webservice)
      end

      # This code is implemented similarly also in application_identity.rb
      # We have it here too as we need the container name for the injection
      # and it simplifies the code to have this specific 2 methods duplicated
      # rather than passing around the ApplicationIdentity object
      def container_name
        container_annotation_value("authn-k8s/#{@service_id}") ||
          container_annotation_value("authn-k8s") ||
          container_annotation_value("kubernetes") ||
          "authenticator"
      end

      def container_annotation_value prefix
        annotation_name = "authentication-container-name"
        annotation = host.annotations.find { |a| a.values[:name] == "#{prefix}/#{annotation_name}" }
        annotation ? annotation[:value] : nil
      end

      def audit_failure(err)
        authenticator_input = Authentication::AuthenticatorInput.new(
          authenticator_name: 'authn-k8s',
          service_id:         @service_id,
          account:            @conjur_account,
          username:           host_id,
        )

        @audit_event.(
          authenticator_input: authenticator_input,
            success: false,
            message: err.message
        )
      end
    end
  end
end
